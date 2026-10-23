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
DYN_SYMBOLS = "  234: 00000000    50 FUNC GLOBAL DEFAULT 13 webkit_web_view_get_wpe_view"


class LinkedWpeElfTest(unittest.TestCase):
    def inspect(self, h=HEADER, d=DYNAMIC, v=VERSIONS, sym=DYN_SYMBOLS):
        return gate.inspect_elf(h, d, v, sym)

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

    def test_platform_export_is_mandatory(self):
        self.assertIn("MISSING_WPE_PLATFORM_ENTRYPOINT",
                      self.inspect(sym="")["WPE_LIBRARY_ISSUES"])
        undefined = "  1: 000000 0 FUNC GLOBAL DEFAULT UND webkit_web_view_get_wpe_view"
        self.assertIn("MISSING_WPE_PLATFORM_ENTRYPOINT",
                      self.inspect(sym=undefined)["WPE_LIBRARY_ISSUES"])

    def test_media_free_gstreamer_dependency_is_forbidden(self):
        d = DYNAMIC + "0x1 (NEEDED) Shared library: [libgstreamer-1.0.so.0]\n"
        self.assertIn("GSTREAMER_DEPENDENCY_IN_MEDIA_FREE_BUILD",
                      self.inspect(d=d)["WPE_LIBRARY_ISSUES"])

    def test_undefined_gst_cat_default_is_forbidden(self):
        sym = DYN_SYMBOLS + "\n  99: 0 0 OBJECT GLOBAL DEFAULT UND GST_CAT_DEFAULT@GST_1.0"
        self.assertIn("UNDEFINED_GST_CAT_DEFAULT",
                      self.inspect(sym=sym)["WPE_LIBRARY_ISSUES"])

    def test_outlined_gcc15_helpers_must_not_remain_undefined(self):
        bad = DYN_SYMBOLS + (
            "\n  75: 00000000 0 FUNC GLOBAL DEFAULT UND __aarch64_ldadd4_relax"
            "\n  76: 00000000 0 FUNC GLOBAL DEFAULT UND __aarch64_cas4_acq_rel"
            "\n  77: 00000000 0 FUNC GLOBAL DEFAULT UND __aarch64_swp4_acq_rel")
        result = self.inspect(sym=bad)
        self.assertIn("UNDEFINED_GCC15_OUTLINED_ATOMICS", result["WPE_LIBRARY_ISSUES"])
        self.assertEqual(result["WPE_GCC15_UNDEFINED_OUTLINED_COUNT"], "3")
        self.assertEqual(result["WPE_LIBRARY_ELF_AUDIT"], "BLOCKED")
        # Locally defined exports are not unresolved references.
        defined = bad.replace("DEFAULT UND __aarch64_", "DEFAULT 11 __aarch64_")
        self.assertNotIn("UNDEFINED_GCC15_OUTLINED_ATOMICS",
                         self.inspect(sym=defined)["WPE_LIBRARY_ISSUES"])

    def test_atomic16_undefined_requires_target_libatomic_provider(self):
        sym = DYN_SYMBOLS + (
            "\n  90: 00000000 0 FUNC GLOBAL DEFAULT UND __atomic_load_16@LIBATOMIC_1.0"
            "\n  91: 00000000 0 FUNC GLOBAL DEFAULT UND __atomic_store_16@LIBATOMIC_1.0")
        missing = self.inspect(sym=sym)
        self.assertIn("MISSING_LIBATOMIC16_DT_NEEDED", missing["WPE_LIBRARY_ISSUES"])
        self.assertEqual(missing["WPE_ATOMIC16_UNDEFINED_COUNT"], "2")
        linked = self.inspect(sym=sym, d=DYNAMIC +
            "0x1 (NEEDED) Shared library: [libatomic.so.1]\n")
        self.assertNotIn("MISSING_LIBATOMIC16_DT_NEEDED", linked["WPE_LIBRARY_ISSUES"])
        self.assertEqual(linked["WPE_LIBRARY_ELF_AUDIT"], "PASS_STATIC_AARCH64")
        self.assertEqual(linked["WPE_ATOMIC16_PROVIDER_DECLARED"], "true")
        # Presence of libatomic DT_NEEDED does NOT prove provider availability
        # on a real device; private dependency-closure audit remains separate.
        self.assertEqual(linked["WPE_ABI_PROVEN_ON_R36H"], "no")

    def test_glibc_numeric_compare(self):
        self.assertEqual(self.inspect(v="Name: GLIBC_2.9")["WPE_LIBRARY_ELF_AUDIT"],
                         "PASS_STATIC_AARCH64")
        self.assertEqual(self.inspect(v="Name: GLIBC_2.42")["WPE_LIBRARY_ELF_AUDIT"],
                         "BLOCKED")

    def test_textrel_rejected(self):
        self.assertIn("TEXTREL_NOT_ALLOWED",
                      self.inspect(d=DYNAMIC + "\n0x16 (TEXTREL) 0x0")["WPE_LIBRARY_ISSUES"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
