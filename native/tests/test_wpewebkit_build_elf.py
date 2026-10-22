#!/usr/bin/env python3
"""Unit tests for the linked WPEWebKit ELF gate. No target code executed."""
import importlib.util
from pathlib import Path
import unittest

SOURCE = Path(__file__).resolve().parents[2] / "scripts/verify-built-wpewebkit.py"
spec = importlib.util.spec_from_file_location("wpe_link_gate", SOURCE)
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)

HEADER = """ELF Header:
  Class: ELF64
  Data: 2's complement, little endian
  Type: DYN (Shared object file)
  Machine: AArch64
"""
DYNAMIC = """0x0000000000000001 (NEEDED) Shared library: [libc.so.6]
0x000000000000000e (SONAME) Library soname: [libWPEWebKit-2.0.so.1]
"""
VERSIONS = "  0x12: Name: GLIBC_2.41  Flags: none  Version: 3"


class LinkedWpeElfTest(unittest.TestCase):
    def inspect(self, h=HEADER, d=DYNAMIC, v=VERSIONS):
        return gate.inspect_elf(h, d, v)

    def test_valid_target_elf(self):
        r = self.inspect()
        self.assertEqual(r["WPE_LIBRARY_ELF_AUDIT"], "PASS_STATIC_AARCH64")
        self.assertEqual(r["WPE_LIBRARY_GLIBC_MAX"], "2.41")
        self.assertEqual(r["R36H_INSTALLABLE"], "no")

    def test_wrong_cpu_and_endian_rejected(self):
        for h in (HEADER.replace("AArch64", "X86-64"),
                  HEADER.replace("ELF64", "ELF32"),
                  HEADER.replace("little endian", "big endian"),
                  HEADER.replace("DYN", "EXEC")):
            with self.subTest(header=h):
                self.assertEqual(self.inspect(h=h)["WPE_LIBRARY_ELF_AUDIT"], "BLOCKED")

    def test_wrong_soname_rejected(self):
        d = DYNAMIC.replace("libWPEWebKit-2.0.so.1", "libWPEWebKit-1.0.so.1")
        self.assertIn("WRONG_OR_MISSING_SONAME", self.inspect(d=d)["WPE_LIBRARY_ISSUES"])

    def test_glibc_too_new_rejected(self):
        self.assertIn("GLIBC_ABOVE_2_41", self.inspect(v="Name: GLIBC_2.42")["WPE_LIBRARY_ISSUES"])

    def test_host_runpath_rejected(self):
        d = DYNAMIC + "0x1d (RUNPATH) Library runpath: [/home/runner/work/Fire4nix/lib]\n"
        self.assertIn("NONRELOCATABLE_RPATH", self.inspect(d=d)["WPE_LIBRARY_ISSUES"])

    def test_origin_relative_runpath_allowed(self):
        d = DYNAMIC + "0x1d (RUNPATH) Library runpath: [$ORIGIN:$ORIGIN/lib]\n"
        self.assertEqual(self.inspect(d=d)["WPE_LIBRARY_ELF_AUDIT"], "PASS_STATIC_AARCH64")

    def test_missing_and_malicious_needed_rejected(self):
        self.assertIn("NO_DYNAMIC_DEPENDENCIES",
                      self.inspect(d=DYNAMIC.splitlines()[-1])["WPE_LIBRARY_ISSUES"])
        self.assertIn("UNSAFE_DT_NEEDED",
                      self.inspect(d=DYNAMIC.replace("libc.so.6", "../../libc.so.6"))["WPE_LIBRARY_ISSUES"])

    def test_textrel_rejected(self):
        self.assertIn("TEXTREL_NOT_ALLOWED",
                      self.inspect(d=DYNAMIC + "\n0x16 (TEXTREL) 0x0")["WPE_LIBRARY_ISSUES"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
