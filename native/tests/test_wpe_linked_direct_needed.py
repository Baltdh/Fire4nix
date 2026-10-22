#!/usr/bin/env python3
"""No-target-execution regression for linked WPE direct SONAME classification."""
from __future__ import annotations
import importlib.util
from pathlib import Path
import tempfile
import unittest

source = Path(__file__).resolve().parents[2] / "scripts/audit-linked-wpe-direct-needed.py"
spec = importlib.util.spec_from_file_location("wpe_direct", source)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

ARM = ("Class: ELF64\nMachine: AArch64\n"
       "Data: 2's complement, little endian\n")
SONAME = "(SONAME) Library soname: [libWPEWebKit-2.0.so.1]\n"


class WPEEntryAuditTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        self.lib = root / "libWPEWebKit-2.0.so.1"
        self.lib.write_bytes(b"ELF fixture")
        self.stage = root / "stage"
        self.sysroot = root / "sysroot"
        for p in [self.stage, self.sysroot]:
            (p / "usr/lib").mkdir(parents=True)
        self.dynamic = SONAME + "(NEEDED) Shared library: [libc.so.6]\n"
        self.provider_headers = {}
        self.make(self.sysroot, "libc.so.6")

    def make(self, root, name):
        (root / "usr/lib" / name).write_bytes(b"target fixture")

    def mock(self, flag, path):
        if flag == "-h":
            return self.provider_headers.get(path.name, ARM)
        if flag == "-d":
            return self.dynamic if path == self.lib else ""
        if flag == "-V":
            return "Name: GLIBC_2.41"
        raise AssertionError(flag)

    def audit(self):
        return m.audit(self.lib, self.sysroot, self.stage, self.mock)

    def test_sysroot_satisfies_genuine_soname(self):
        result = self.audit()
        self.assertEqual(result["WPE_DIRECT_ELF_NEEDED_STATUS"],
                         "DIRECT_SONAMES_PRESENT_IN_TOOLCHAIN_SYSROOT")
        self.assertEqual(result["WPE_DIRECT_SDK_BUNDLE_EDGES"], 0)
        self.assertEqual(result["R36H_INSTALLABLE"], "no")

    def test_stage_only_requires_bundling(self):
        self.make(self.stage, "libstage.so.1")
        self.dynamic += "(NEEDED) Shared library: [libstage.so.1]\n"
        result = self.audit()
        self.assertEqual(result["WPE_DIRECT_ELF_NEEDED_STATUS"],
                         "STAGE_LIBRARIES_MUST_BE_BUNDLED")
        self.assertEqual(result["WPE_DIRECT_BUNDLE_REQUIRED"], ["libstage.so.1"])
        self.assertEqual(result["WPE_DIRECT_SDK_BUNDLE_EDGES"], 1)

    def test_sysroot_provider_preferred_over_stage(self):
        self.make(self.stage, "libc.so.6")
        self.assertEqual(self.audit()["WPE_DIRECT_BUNDLE_REQUIRED"], [])

    def test_missing_dependency_blocked(self):
        self.dynamic += "(NEEDED) Shared library: [libmissing.so.9]\n"
        result = self.audit()
        self.assertEqual(result["WPE_DIRECT_ELF_NEEDED_STATUS"], "BLOCKED")
        self.assertEqual(result["WPE_DIRECT_MISSING"], ["libmissing.so.9"])

    def test_wrong_arch_provider_blocked(self):
        self.provider_headers["libc.so.6"] = ARM.replace("AArch64", "X86-64")
        self.assertIn("PROVIDER_WRONG_ARCH:libc.so.6",
                      self.audit()["WPE_DIRECT_INVALID"])

    def test_gstreamer_and_unsafe_needed_blocked(self):
        self.dynamic += "(NEEDED) Shared library: [libgstreamer-1.0.so.0]\n"
        self.dynamic += "(NEEDED) Shared library: [../../host.so]\n"
        result = self.audit()
        self.assertEqual(result["WPE_DIRECT_ELF_NEEDED_STATUS"], "BLOCKED")
        self.assertTrue(any("GSTREAMER" in x for x in result["WPE_DIRECT_INVALID"]))
        self.assertTrue(any("UNSAFE" in x for x in result["WPE_DIRECT_INVALID"]))

    def test_unknown_and_broken_links_not_providers(self):
        (self.stage / "usr/lib/libescape.so.1").symlink_to("/etc/passwd")
        self.dynamic += "(NEEDED) Shared library: [libescape.so.1]\n"
        self.assertIn("libescape.so.1", self.audit()["WPE_DIRECT_MISSING"])

    def test_older_wrong_class_and_glibc(self):
        self.provider_headers["libc.so.6"] = ARM.replace("ELF64", "ELF32")
        self.assertEqual(self.audit()["WPE_DIRECT_ELF_NEEDED_STATUS"], "BLOCKED")


if __name__ == "__main__":
    unittest.main(verbosity=2)
