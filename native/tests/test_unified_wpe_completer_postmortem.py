#!/usr/bin/env python3
"""Unit tests for actual unified WPE artifact postmortem (not a device test)."""
from pathlib import Path
import importlib.util
import tempfile
import unittest

FILE = Path(__file__).resolve().parents[2] / "scripts/inspect-unified-wpe-completed-artifact.py"
spec = importlib.util.spec_from_file_location("unified_wpe_postmortem", FILE)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class UnifiedArtifactPostmortem(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.runtime = self.root / "private-wpe-runtime-sdk-closed"
        self.runtime.mkdir()
        self.report_dir = self.root / "report"
        self.report_dir.mkdir()

    def assets(self):
        for path, _ in module.ELF_NAMES:
            file = self.runtime / path
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_bytes(b"fixture" * 26)
        res = self.runtime / module.RESOURCE
        res.parent.mkdir(parents=True, exist_ok=True)
        res.write_bytes(b"gresource test only")

    def status(self, last="PASS_REAL_AARCH64", exit_code=0):
        (self.report_dir / "wpe-subprocesses-result.txt").write_text(
            "WPE_SUBPROCESS_BUILD=START_REAL_ROCKNIX_AARCH64\n"
            f"WPE_SUBPROCESS_CMAKE_EXIT={exit_code}\n"
            f"WPE_SUBPROCESS_BUILD={last}\n")

    def test_failure_after_link_can_be_diagnosed_but_not_released(self):
        self.assets()
        self.status()
        result = module.analyze(self.root, "failure", lambda file: [])
        self.assertIn("WPE_UNIFIED_ALL_ASSETS_PRESENT_STATIC=yes", result)
        self.assertIn("WPE_UNIFIED_LINKED_BUT_WORKFLOW_FAILED=yes", result)
        self.assertIn("WPE_UNIFIED_RELEASE_GATE=FAILED_WORKFLOW_NO_RELEASE", result)
        self.assertIn("R36H_INSTALLABLE=no", result)
        self.assertIn("WPE_UNIFIED_RUNTIME_SOURCE=CLOSED_SDK_RUNTIME", result)
        for _, label in module.ELF_NAMES:
            self.assertIn(f"WPE_UNIFIED_{label}=PASS_ELF_STATIC_ONLY", result)

    def test_source_success_still_requires_independent_device_gates(self):
        self.assets()
        self.status()
        result = module.analyze(self.root, "success", lambda file: [])
        self.assertIn("WPE_UNIFIED_LINKED_BUT_WORKFLOW_FAILED=no", result)
        self.assertIn("SEPARATE_ABI_AND_PACKAGING_GATES_REQUIRED", result)
        self.assertNotIn("R36H_INSTALLABLE=yes", result)

    def test_no_artifact_or_report_never_claims_binary_success(self):
        result = module.analyze(self.root, "failure", lambda file: [])
        self.assertIn("WPE_UNIFIED_RUNTIME_SOURCE=NO_STAGED_RUNTIME", result)
        self.assertIn("WPE_UNIFIED_ALL_ASSETS_PRESENT_STATIC=no", result)
        self.assertIn("WPE_UNIFIED_BUILD_RESULT=NOT_REPORTED", result)

    def test_prebundle_cannot_claim_closed_runtime(self):
        self.runtime.rename(self.root / "private-wpe-runtime")
        self.runtime = self.root / "private-wpe-runtime"
        self.assets()
        result = module.analyze(self.root, "failure", lambda file: [])
        self.assertIn("WPE_UNIFIED_RUNTIME_SOURCE=UNBUNDLED_PRIVATE_RUNTIME", result)
        self.assertIn("WPE_UNIFIED_LINKED_BUT_WORKFLOW_FAILED=no", result)

    def test_missing_resource_and_bad_elf_block_completeness(self):
        self.assets()
        self.status()
        (self.runtime / module.RESOURCE).unlink()
        result = module.analyze(self.root, "failure", lambda file: [])
        self.assertIn("WPE_UNIFIED_INSPECTOR_RESOURCE=MISSING_OR_UNSAFE", result)
        self.assertIn("WPE_UNIFIED_ALL_ASSETS_PRESENT_STATIC=no", result)
        (self.runtime / module.RESOURCE).write_bytes(b"restored")
        result = module.analyze(
            self.root, "failure",
            lambda file: ["WRONG_MACHINE"] if file.name == "WPEWebProcess" else [])
        self.assertIn("WPE_UNIFIED_WEB_PROCESS=REJECTED_ELF_STATIC", result)
        self.assertIn("WPE_UNIFIED_FINDING=WEB_PROCESS:WRONG_MACHINE", result)
        self.assertIn("WPE_UNIFIED_ALL_ASSETS_PRESENT_STATIC=no", result)

    def test_reject_symlink_and_multiple_staged_runtime(self):
        self.assets()
        path = self.runtime / "lib/libWPEWebKit-2.0.so.1"
        path.unlink()
        path.symlink_to("/etc/passwd")
        result = module.analyze(self.root, "failure", lambda file: [])
        self.assertIn("WPE_UNIFIED_WEBKIT=MISSING_OR_UNSAFE", result)
        (self.root / "private-wpe-runtime").mkdir()
        # Two different stage names are intentional; prefer the closed one.
        result = module.analyze(self.root, "failure", lambda file: [])
        self.assertIn("WPE_UNIFIED_RUNTIME_SOURCE=CLOSED_SDK_RUNTIME", result)
        clone = self.root / "other" / "private-wpe-runtime-sdk-closed"
        clone.mkdir(parents=True)
        with self.assertRaisesRegex(ValueError, "AMBIGUOUS_ARTIFACT_DIRECTORY"):
            module.analyze(self.root, "failure", lambda file: [])

    def test_report_transitions_and_conflicts(self):
        self.status(last="BLOCKED", exit_code=10)
        result = module.analyze(self.root, "failure", lambda file: [])
        self.assertIn("WPE_UNIFIED_BUILD_RESULT=BLOCKED", result)
        self.assertIn("WPE_UNIFIED_CMAKE_EXIT=10", result)
        file = self.report_dir / "wpe-subprocesses-result.txt"
        file.write_text("WPE_SUBPROCESS_CMAKE_EXIT=0\nWPE_SUBPROCESS_CMAKE_EXIT=10\n")
        with self.assertRaisesRegex(ValueError, "CONFLICTING_BUILD_RESULT"):
            module.analyze(self.root, "failure", lambda file: [])

    def test_reject_ambiguous_or_symlink_result(self):
        self.status()
        (self.root / "backup" / "report").mkdir(parents=True)
        (self.root / "backup" / "report" / "wpe-subprocesses-result.txt").write_text(
            "WPE_SUBPROCESS_CMAKE_EXIT=0\n")
        with self.assertRaisesRegex(ValueError, "AMBIGUOUS_BUILD_RESULT"):
            module.analyze(self.root, "failure", lambda file: [])
        (self.root / "backup" / "report" / "wpe-subprocesses-result.txt").unlink()
        file = self.report_dir / "wpe-subprocesses-result.txt"
        file.unlink()
        file.symlink_to("/etc/hosts")
        with self.assertRaisesRegex(ValueError, "UNSAFE_BUILD_RESULT"):
            module.analyze(self.root, "failure", lambda file: [])

    def test_reject_unfinished_source_conclusion(self):
        with self.assertRaisesRegex(ValueError, "ONLY_COMPLETED"):
            module.analyze(self.root, "in_progress", lambda file: [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
