#!/usr/bin/env python3
"""Regression: WebKit runtime checksums must not buffer a whole ELF in memory."""
import hashlib
import importlib.util
from pathlib import Path
from unittest import TestCase, main, mock
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/package-first-r36h-ports-candidate.py"
spec = importlib.util.spec_from_file_location("fire4nix_ports_packager", SCRIPT)
packager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packager)


class StreamingHashTests(TestCase):
    def test_sha256_streams_without_path_read_bytes(self):
        with tempfile.TemporaryDirectory() as tmp:
            payload = Path(tmp) / "large-library.so.1"
            # Enough data to exercise repeated reads without burdening CI.
            payload.write_bytes(b"WebKit" * 1024 * 1024)
            expected = hashlib.sha256(b"WebKit" * 1024 * 1024).hexdigest()
            with mock.patch.object(Path, "read_bytes", side_effect=AssertionError("whole-file read")):
                self.assertEqual(packager.sha256_file(payload), expected)

    def test_runtime_checksum_verification_streams(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            files = sorted(set(packager.NAMES) |
                           {"share/wpe-webkit-2.0/inspector.gresource"})
            rows = []
            for i, relative in enumerate(files):
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                payload = (f"payload-{i}".encode()) * 256
                path.write_bytes(payload)
                rows.append(f"{hashlib.sha256(payload).hexdigest()}  {relative}")
            (root / "SHA256SUMS.txt").write_text("\n".join(rows) + "\n")
            with mock.patch.object(Path, "read_bytes", side_effect=AssertionError("whole-file read")):
                packager.verify_checksums(root)
            (root / files[0]).write_bytes(b"tampered")
            with self.assertRaisesRegex(ValueError, "RUNTIME_HASH_MISMATCH"):
                packager.verify_checksums(root)


if __name__ == "__main__":
    main(verbosity=2)
