#!/usr/bin/env python3
"""Regressions for static DT_NEEDED lookup (no real target ELF executed)."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[2] / "scripts/audit-rocknix-sdk-elf-closure.py"
spec = importlib.util.spec_from_file_location("elf_stage", SOURCE)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

AARCH64 = """ELF Header:
  Class:                             ELF64
  Data:                              2's complement, little endian
  Machine:                           AArch64
"""

class StaticELFClosureTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.stage, self.sysroot = root/"stage", root/"sysroot"
        for base in (self.stage, self.sysroot):
            (base/"usr/lib").mkdir(parents=True)

    def make(self, base, name):
        f = base/"usr/lib"/name
        f.write_bytes(b"ELF TEST FIXTURE")
        return f

    def test_architecture_rejection(self):
        self.assertTrue(m.is_aarch64(AARCH64))
        self.assertFalse(m.is_aarch64(AARCH64.replace("AArch64", "ARM")))
        self.assertFalse(m.is_aarch64(AARCH64.replace("ELF64", "ELF32")))
        self.assertFalse(m.is_aarch64(AARCH64.replace("little endian", "big endian")))

    def test_unknown_dependency_is_reported(self):
        self.make(self.stage, "libfire4nix.so.1")
        def fake_readelf(flag, path):
            return { "-h": AARCH64,
                "-d": " 0x1 (NEEDED) Shared library: [libmissing.so.9]",
                "-V": "No version information found" }[flag]
        with patch.object(m, "readelf", side_effect=fake_readelf):
            result = m.audit(self.stage, self.sysroot)
        self.assertEqual(result["MISSING_EDGES"], 1)
        self.assertIn("usr/lib/libfire4nix.so.1:libmissing.so.9",
                      result["MISSING_NEEDED"])

    def test_stage_library_resolves_before_sysroot(self):
        self.make(self.stage, "libfire4nix.so.1")
        self.make(self.stage, "libneeded.so.1")
        self.make(self.sysroot, "libneeded.so.1")
        def fake_readelf(flag, path):
            if flag == "-h": return AARCH64
            if flag == "-V": return ""
            if path.name == "libfire4nix.so.1":
                return "(NEEDED) Shared library: [libneeded.so.1]"
            return ""
        with patch.object(m, "readelf", side_effect=fake_readelf):
            r = m.audit(self.stage, self.sysroot)
        self.assertEqual(r["RESOLVED_FROM_STAGE"], 1)
        self.assertEqual(r["MISSING_EDGES"], 0)

    def test_escaped_symlink_is_reported(self):
        external = Path(self.tmp.name)/"libexternal.so.1"
        external.write_bytes(b"external")
        (self.stage/"usr/lib/libexternal.so.1").symlink_to(external)
        _, unsafe = m.safe_index(self.stage)
        self.assertEqual(len(unsafe), 1)

    def test_absolute_runpath_is_blocked(self):
        self.make(self.stage, "libfire4nix.so.1")
        def fake_readelf(flag, path):
            return {"-h": AARCH64, "-V": "",
                    "-d": "(RUNPATH) Library runpath: [/home/runner/unsafe]"
                    }[flag]
        with patch.object(m, "readelf", side_effect=fake_readelf):
            result = m.audit(self.stage, self.sysroot)
        self.assertEqual(result["UNSAFE_PATHS"], 1)

    def test_newer_glibc_is_reported(self):
        self.make(self.stage, "libfire4nix.so.1")
        def fake_readelf(flag, path):
            return {"-h": AARCH64, "-d": "",
                    "-V": "Name: GLIBC_2.44  Flags: none"
                    }[flag]
        with patch.object(m, "readelf", side_effect=fake_readelf):
            result = m.audit(self.stage, self.sysroot)
        self.assertEqual(result["NEWER_GLIBC_REFERENCES"], 1)

if __name__ == "__main__":
    unittest.main(verbosity=2)
