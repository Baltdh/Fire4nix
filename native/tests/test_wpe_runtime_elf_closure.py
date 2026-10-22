#!/usr/bin/env python3
"""Host-only functional tests of the WPE runtime closure audit."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/audit-wpe-runtime-closure.py"
spec = importlib.util.spec_from_file_location("fire4nix_wpe_closure", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

ARM64 = ("Class: ELF64\n"
         "Data: 2's complement, little endian\n"
         "Machine: AArch64\n")
SONAME = "0x0e (SONAME) Library soname: [libWPEWebKit-2.0.so.1]\n"


class RuntimeClosureTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.runtime = self.root / "runtime"
        self.sysroot = self.root / "sysroot"
        self.stage = self.root / "stage"
        for sub in ("runtime/lib", "runtime/libexec/wpe-webkit-2.0",
                    "sysroot/usr/lib", "stage/usr/lib"):
            (self.root / sub).mkdir(parents=True)
        self.create(self.runtime / "lib/libWPEWebKit-2.0.so.1")
        self.create(self.runtime / "libexec/wpe-webkit-2.0/WPEWebProcess")
        self.create(self.runtime / "libexec/wpe-webkit-2.0/WPENetworkProcess")
        self.create(self.sysroot / "usr/lib/libc.so.6")
        (self.runtime / "BUILD-REPORT.txt").write_text(
            "GPU_PROCESS_PROFILE=disabled_verified_wayland\n")
        self.headers = {}
        self.dynamics = {
            "libWPEWebKit-2.0.so.1": SONAME + "0x01 (NEEDED) Shared library: [libc.so.6]\n",
            "WPEWebProcess": "0x01 (NEEDED) Shared library: [libWPEWebKit-2.0.so.1]\n",
            "WPENetworkProcess": "0x01 (NEEDED) Shared library: [libc.so.6]\n",
            "libc.so.6": "",
        }
        self.versions = {}

    @staticmethod
    def create(path):
        path.write_bytes(b"\x7fELFfixture")

    def elf(self, flag, path):
        if flag == "-h":
            return self.headers.get(path.name, ARM64)
        if flag == "-d":
            return self.dynamics.get(path.name, "")
        if flag == "-V":
            return self.versions.get(path.name, "Name: GLIBC_2.41\n")
        raise AssertionError(flag)

    def run_audit(self):
        return module.audit(self.runtime, self.sysroot, self.stage, self.elf)

    def test_valid_sdk_static_not_infer_installable(self):
        r = self.run_audit()
        self.assertEqual(r["WPE_RUNTIME_CLOSURE"], "SDK_STATIC_CANDIDATES_ONLY")
        self.assertEqual(r["WPE_SCANNED_ELFS"], 4)
        self.assertEqual(r["WPE_REQUIRED_PROCESSES"], "WPEWebProcess,WPENetworkProcess")
        self.assertEqual(r["R36H_INSTALLABLE"], "no")

    def test_missing_transitive_soname_is_blocked(self):
        self.dynamics["libc.so.6"] = "0x01 (NEEDED) Shared library: [libmissing.so.99]\n"
        self.assertIn("libc.so.6:libmissing.so.99", self.run_audit()["WPE_MISSING_SONAMES"])
        self.assertEqual(self.run_audit()["WPE_RUNTIME_CLOSURE"], "BLOCKED")

    def test_stage_only_is_not_runtime_proof(self):
        self.create(self.stage / "usr/lib/libprivate.so.1")
        self.dynamics["libWPEWebKit-2.0.so.1"] += (
            "0x01 (NEEDED) Shared library: [libprivate.so.1]\n")
        result = self.run_audit()
        self.assertEqual(result["WPE_STAGE_ONLY_DEPENDENCIES"],
                         ["libWPEWebKit-2.0.so.1:libprivate.so.1"])
        self.assertEqual(result["R36H_INSTALLABLE"], "no")

    def test_reject_wrong_elf_arch_and_glibc(self):
        self.headers["WPEWebProcess"] = ARM64.replace("AArch64", "X86-64")
        self.assertIn("INVALID_AARCH64_ELF:WPEWebProcess", self.run_audit()["WPE_ABI_FINDINGS"])
        self.headers.clear()
        self.versions["WPENetworkProcess"] = "Name: GLIBC_2.42\n"
        self.assertIn("NEWER_GLIBC:WPENetworkProcess:2.42",
                      self.run_audit()["WPE_ABI_FINDINGS"])

    def test_reject_absolute_ci_rpath(self):
        self.dynamics["libWPEWebKit-2.0.so.1"] += (
            "0x001d (RUNPATH) Library runpath: [/home/runner/work/sdk]\n")
        self.assertTrue(any("UNSAFE_RPATH" in row for row in
                            self.run_audit()["WPE_ABI_FINDINGS"]))

    def test_accept_relocatable_origin_rpath(self):
        self.dynamics["libWPEWebKit-2.0.so.1"] += (
            "0x001d (RUNPATH) Library runpath: [$ORIGIN:$ORIGIN/other]\n")
        self.assertFalse(self.run_audit()["WPE_ABI_FINDINGS"])

    def test_reject_gstreamer_and_unsafe_needed(self):
        self.dynamics["WPEWebProcess"] += (
            "0x01 (NEEDED) Shared library: [libgstbase-1.0.so.0]\n"
            "0x01 (NEEDED) Shared library: [../../host/libevil.so]\n")
        findings = self.run_audit()["WPE_ABI_FINDINGS"]
        self.assertTrue(any("GSTREAMER" in f for f in findings))
        self.assertTrue(any("UNSAFE_NEEDED" in f for f in findings))

    def test_missing_gpu_profile_requires_process(self):
        (self.runtime / "BUILD-REPORT.txt").unlink()
        with self.assertRaisesRegex(ValueError, "MISSING_OR_ESCAPING"):
            self.run_audit()
        self.create(self.runtime / "libexec/wpe-webkit-2.0/WPEGPUProcess")
        self.dynamics["WPEGPUProcess"] = "0x01 (NEEDED) Shared library: [libc.so.6]\n"
        self.assertIn("WPEGPUProcess", self.run_audit()["WPE_REQUIRED_PROCESSES"])

    def test_reject_ambiguous_gpu_profile(self):
        (self.runtime / "BUILD-REPORT.txt").write_text(
            "GPU_PROCESS_PROFILE=disabled_verified_wayland\n"
            "GPU_PROCESS_PROFILE=enabled_verified\n")
        with self.assertRaisesRegex(ValueError, "CONFLICTING_GPU_PROFILES"):
            self.run_audit()

    def test_reject_escape_and_broken_links(self):
        (self.runtime / "lib/libescape.so.1").symlink_to("/etc/passwd")
        self.assertTrue(any("UNSAFE_LINK" in f for f in
                            self.run_audit()["WPE_ABI_FINDINGS"]))

    def test_soname_required_not_just_filename(self):
        self.dynamics["libWPEWebKit-2.0.so.1"] = (
            "0x0e (SONAME) Library soname: [libWPEWebKit-1.0.so.1]\n")
        self.assertTrue(any("INVALID_WPE_SONAME" in f for f in
                            self.run_audit()["WPE_ABI_FINDINGS"]))


if __name__ == "__main__":
    unittest.main(verbosity=2)
