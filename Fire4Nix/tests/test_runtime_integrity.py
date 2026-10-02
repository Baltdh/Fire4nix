import hashlib
import os
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest

VERIFY = Path(__file__).resolve().parents[1] / "scripts/verify_wpe_runtime.sh"

class RuntimeIntegrityTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        # Minimal ELF header for architecture identification, not execution.
        elf = bytearray(64)
        elf[:16] = b"\x7fELF\x02\x01\x01" + bytes(9)
        struct.pack_into("<HHI", elf, 16, 3, 183, 1)
        self.paths = [self.root / "lib/libWPEWebKit-2.0.so.1"]
        self.paths += [self.root / "libexec/wpe-webkit-2.0" / name
                       for name in ("WPEWebProcess", "WPENetworkProcess", "WPEGPUProcess")]
        for path in self.paths:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(elf)
            path.chmod(0o755)
        self.manifest = self.root / "runtime.manifest"
        self.manifest.write_text("[sha256]\n" + "".join(
            hashlib.sha256(p.read_bytes()).hexdigest() + "  " +
            p.relative_to(self.root).as_posix() + "\n" for p in self.paths))

    def tearDown(self):
        self.tmp.cleanup()

    def check_runtime(self):
        return subprocess.run(["sh", str(VERIFY), str(self.root)],
                              capture_output=True, text=True).returncode

    def test_valid_runtime(self):
        self.assertEqual(self.check_runtime(), 0)

    def test_library_symlink(self):
        (self.root / "lib/libWPEWebKit-2.0.so").symlink_to(self.paths[0].name)
        self.assertEqual(self.check_runtime(), 0)

    def test_corrupted_library(self):
        with self.paths[0].open("ab") as out:
            out.write(b"corruption")
        self.assertNotEqual(self.check_runtime(), 0)

    def test_nonexecutable_process(self):
        self.paths[1].chmod(0o644)
        self.assertNotEqual(self.check_runtime(), 0)

    def test_manifest_path_traversal(self):
        with self.manifest.open("a") as out:
            out.write("0" * 64 + "  lib/../../outside\n")
        self.assertNotEqual(self.check_runtime(), 0)

    def test_empty_manifest(self):
        self.manifest.write_text("[sha256]\n")
        self.assertNotEqual(self.check_runtime(), 0)

if __name__ == "__main__":
    unittest.main()
