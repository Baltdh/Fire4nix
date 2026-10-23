#!/usr/bin/env python3
"""Host-only regressions: build RPATH is temporary, installed RPATH is strict."""
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/audit-wpe-process-rpath.py"
spec = importlib.util.spec_from_file_location("wpe_installed_process_rpath", SCRIPT)
auditor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(auditor)
BASIC = "0x00000001 (NEEDED) Shared library: [libc.so.6]\n"


class InstalledElfRpathTest(unittest.TestCase):
    def test_installed_no_rpath(self):
        auditor.verify_dynamic(BASIC)

    def test_install_allows_private_origin_subpaths(self):
        auditor.verify_dynamic(
            BASIC + "0x1d (RUNPATH) Library runpath: [$ORIGIN:$ORIGIN/../../bad]\n"
            .replace("$ORIGIN/../../bad", "$ORIGIN/lib"))
        auditor.verify_dynamic(BASIC + "0x1d (RPATH) Library rpath: [$ORIGIN]\n")

    def test_absolute_host_paths_rejected(self):
        for value in (
            "/home/runner/work/Fire4nix",
            "$ORIGIN:/home/runner/SDK",
            "/tmp/rocknix-sdk:$ORIGIN",
            "$ORIGIN/../stage",
            "$ORIGIN/../../usr/lib",
            "",
            "lib",
            "$LIB",
        ):
            with self.subTest(value=value):
                dynamic = BASIC + f"0x1d (RUNPATH) Library runpath: [{value}]\n"
                with self.assertRaisesRegex(ValueError, "NON_PORTABLE_INSTALLED_RPATH"):
                    auditor.verify_dynamic(dynamic)

    def test_missing_dynamic_needed_rejected(self):
        with self.assertRaisesRegex(ValueError, "MISSING_DYNAMIC_DEPENDENCIES"):
            auditor.verify_dynamic("There is no dynamic section in this file.")

    def test_real_build_checks_only_installed_elf_rpath(self):
        build = (ROOT / "scripts/build-wpe2541-subprocesses-rocknix.sh").read_text()
        self.assertIn("WPE_PROCESS_BUILD_TREE_RPATH=DEFERRED_UNTIL_INSTALL", build)
        self.assertIn('python3 "$repo_root/scripts/audit-wpe-process-rpath.py" "$installed"', build)
        self.assertIn("WPE_INSTALLED_PROCESS_RPATH=PASS_RELOCATABLE", build)
        self.assertLess(build.index('DESTDIR="$dest" cmake --install'),
                        build.index('python3 "$repo_root/scripts/audit-wpe-process-rpath.py"'))
        self.assertLess(build.index('WPE_INSTALLED_PROCESS_RPATH=PASS_RELOCATABLE'),
                        build.index('sh "$repo_root/rocknix-integration/stage-wpe-runtime.sh" --stage'))


if __name__ == "__main__":
    unittest.main(verbosity=2)
