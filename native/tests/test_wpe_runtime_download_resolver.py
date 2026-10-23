#!/usr/bin/env python3
"""Ensure GitHub artifact path selection refuses incomplete or ambiguous engine output."""
from pathlib import Path
import importlib.util
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/resolve-wpe-runtime-download.py"
spec = importlib.util.spec_from_file_location("wpe_zip_download_resolver", SCRIPT)
resolver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(resolver)


class ResolveRealRuntimeDownloadTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.download = Path(temp.name) / "download"
        self.download.mkdir()

    def populate(self, layout):
        out = self.download / layout
        for relative in resolver.REQUIRED:
            file = out / relative
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_bytes(b"real WPE path selection fixture")
        return out

    def test_github_least_common_ancestor_layout(self):
        root = self.populate("private-wpe-runtime-sdk-closed")
        self.assertEqual(resolver.resolve(self.download), root)

    def test_legacy_prefixed_layout(self):
        root = self.populate("wpe-unified-sdk-build/private-wpe-runtime-sdk-closed")
        self.assertEqual(resolver.resolve(self.download), root)

    def test_missing_artifact_rejected(self):
        with self.assertRaisesRegex(ValueError, "EXPECTED_ONE"):
            resolver.resolve(self.download)

    def test_partial_wpe_payload_rejected(self):
        root = self.populate("private-wpe-runtime-sdk-closed")
        (root / "libexec/wpe-webkit-2.0/WPENetworkProcess").unlink()
        with self.assertRaisesRegex(ValueError, "WPENetworkProcess"):
            resolver.resolve(self.download)

    def test_two_possible_runtimes_rejected(self):
        for layout in resolver.LAYOUTS:
            self.populate(layout)
        with self.assertRaisesRegex(ValueError, "EXPECTED_ONE"):
            resolver.resolve(self.download)

    def test_symlinked_root_rejected(self):
        original = self.populate("private-wpe-runtime-sdk-closed")
        original.rename(self.download / "real")
        original.symlink_to(self.download / "real", target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "SYMLINKED"):
            resolver.resolve(self.download)

    def test_symlinked_required_file_rejected(self):
        root = self.populate("private-wpe-runtime-sdk-closed")
        file = root / resolver.REQUIRED[0]
        file.unlink()
        file.symlink_to("/etc/passwd")
        with self.assertRaisesRegex(ValueError, "MISSING_OR_UNSAFE"):
            resolver.resolve(self.download)


if __name__ == "__main__":
    unittest.main(verbosity=2)
