#!/usr/bin/env python3
"""Safely replay a real WPE stage; no hardware/ELF execution in these tests."""
from __future__ import annotations
import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
P = ROOT / "scripts/recover-preclosed-wpe-stage.py"
spec = importlib.util.spec_from_file_location("wpe_preclosure_replay", P)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class ReplayStageTests(unittest.TestCase):
    def setUp(self):
        ctx = tempfile.TemporaryDirectory()
        self.addCleanup(ctx.cleanup)
        self.home = Path(ctx.name)
        self.download = self.home / "actions-download"
        self.runtime = self.download / "private-wpe-runtime"
        self.runtime.mkdir(parents=True)
        self.output = self.home / "recovered"
        (self.runtime / "BUILD-REPORT.txt").write_text(
            "GPU_PROCESS_PROFILE=disabled_verified_wayland\n"
            "WPE_INSTALLED_ASSETS_PROFILE=strict\n"
            "WPE_INSTALLED_ASSETS_STATUS=copied_and_static_elf_checked\n")
        self.versioned = self.runtime / "lib/libWPEWebKit-2.0.so.1.11.4"
        self.versioned.parent.mkdir(parents=True)
        self.versioned.write_bytes(b"aarch64-wpewebkit-real-hash-fixture")
        self.sha = {}
        for relative in module.REQUIRED[2:]:
            f = self.runtime / relative
            if relative == "lib/libWPEWebKit-2.0.so.1":
                source = self.versioned
            else:
                f.parent.mkdir(parents=True, exist_ok=True)
                f.write_bytes(relative.encode())
                source = f
            self.sha[relative] = hashlib.sha256(source.read_bytes()).hexdigest()
        (self.runtime / "SHA256SUMS.txt").write_text(
            "".join(f"{sha}  {path}\n" for path, sha in self.sha.items()))

    def test_recover_preclosure_alias_without_forging_report(self):
        result = module.recover(self.download, self.output)
        self.assertEqual(result["hashed"], len(module.REQUIRED) - 2)
        self.assertEqual(result["repaired"], ["lib/libWPEWebKit-2.0.so.1"])
        self.assertEqual((self.output / "lib/libWPEWebKit-2.0.so.1").read_bytes(),
                         self.versioned.read_bytes())
        self.assertFalse((self.output / "SDK-BUNDLE-REPORT.txt").exists())
        self.assertFalse((self.runtime / "lib/libWPEWebKit-2.0.so.1").exists())

    def test_tampered_required_elf_rejected(self):
        (self.runtime / "libexec/wpe-webkit-2.0/WPEWebProcess").write_bytes(b"modified")
        with self.assertRaisesRegex(ValueError, "WPE_SHA256_VERIFICATION_FAILED"):
            module.recover(self.download, self.output)
        self.assertFalse(self.output.exists())

    def test_broken_provenance_rejected(self):
        (self.runtime / "BUILD-REPORT.txt").write_text("GPU_PROCESS_PROFILE=unverified\n")
        with self.assertRaisesRegex(ValueError, "UNVERIFIED_WPE_BUILD_PROFILE"):
            module.recover(self.download, self.output)

    def test_file_symlink_outside_stage_rejected(self):
        p = self.runtime / "libexec/wpe-webkit-2.0/WPEWebProcess"
        p.unlink()
        p.symlink_to("/etc/passwd")
        with self.assertRaisesRegex(ValueError, "SYMLINKED_DOWNLOADED_RUNTIME"):
            module.recover(self.download, self.output)

    def test_missing_non_so_asset_cannot_be_repaired(self):
        (self.runtime / "share/wpe-webkit-2.0/inspector.gresource").unlink()
        with self.assertRaisesRegex(ValueError, "UNRECOVERABLE_REQUIRED_FILE"):
            module.recover(self.download, self.output)

    def test_ambiguous_layouts_rejected(self):
        other = self.download / "wpe-unified-sdk-build/private-wpe-runtime"
        other.mkdir(parents=True)
        with self.assertRaisesRegex(ValueError, "EXPECTED_ONE_PRE_CLOSED"):
            module.recover(self.download, self.output)

    def test_reject_manifest_escape(self):
        (self.runtime / "SHA256SUMS.txt").write_text(
            f"{hashlib.sha256(b'bad').hexdigest()}  ../etc/passwd\n")
        with self.assertRaisesRegex(ValueError, "UNSAFE_OR_DUPLICATE_RUNTIME_HASH_PATH"):
            module.recover(self.download, self.output)

    def test_no_overwriting_preexisting_output(self):
        self.output.mkdir()
        with self.assertRaisesRegex(ValueError, "OUTPUT_ALREADY_EXISTS"):
            module.recover(self.download, self.output)

if __name__ == "__main__":
    unittest.main(verbosity=2)
