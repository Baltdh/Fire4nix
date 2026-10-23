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
                    "sysroot/lib", "sysroot/usr/lib", "stage/usr/lib"):
            (self.root / sub).mkdir(parents=True)
        self.create(self.runtime / "lib/libWPEWebKit-2.0.so.1")
        self.create(self.runtime / "libexec/wpe-webkit-2.0/WPEWebProcess")
        self.create(self.runtime / "libexec/wpe-webkit-2.0/WPENetworkProcess")
        self.create(self.sysroot / "usr/lib/libc.so.6")
        self.create(self.sysroot / "lib/ld-linux-aarch64.so.1")
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
        self.interps = {
            "WPEWebProcess": "      [Requesting program interpreter: /lib/ld-linux-aarch64.so.1]\\n",
            "WPENetworkProcess": "      [Requesting program interpreter: /lib/ld-linux-aarch64.so.1]\\n",
        }

    @staticmethod
    def create(path):
        path.write_bytes(b"\x7fELFfixture")

    def elf(self, flag, path):
        if flag == "-h":
            return self.headers.get(path.name, ARM64)
        if flag == "-d":
            return self.dynamics.get(path.name, "")
        if flag == "-l":
            return self.interps.get(path.name, "")
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
        self.assertEqual(r["WPE_PT_INTERP_CHECKS"], 2)
        self.assertEqual(r["WPE_PT_INTERP_PROVEN_ON_R36H"], "no")
        self.assertEqual(r["R36H_INSTALLABLE"], "no")

    def add_strict_installed_assets(self):
        module = (self.runtime /
                  "lib/wpe-webkit-2.0/injected-bundle/libWPEInjectedBundle.so")
        module.parent.mkdir(parents=True, exist_ok=True)
        self.create(module)
        resource = self.runtime / "share/wpe-webkit-2.0/inspector.gresource"
        resource.parent.mkdir(parents=True, exist_ok=True)
        resource.write_bytes(b"real-resource-fixture")
        (self.runtime / "BUILD-REPORT.txt").write_text(
            "GPU_PROCESS_PROFILE=disabled_verified_wayland\\n"
            "WPE_INSTALLED_ASSETS_PROFILE=strict\\n"
            "WPE_INSTALLED_ASSETS_STATUS=copied_and_static_elf_checked\\n")
        self.dynamics["libWPEInjectedBundle.so"] = (
            "0x01 (NEEDED) Shared library: [libc.so.6]\\n")
        return module, resource

    def test_injected_bundle_checked_as_independent_elf_root(self):
        self.add_strict_installed_assets()
        result = self.run_audit()
        self.assertEqual(result["WPE_RUNTIME_CLOSURE"], "SDK_STATIC_CANDIDATES_ONLY")
        self.assertEqual(result["WPE_SCANNED_ELFS"], 5)
        self.assertEqual(result["WPE_INJECTED_BUNDLE_INCLUDED_IN_CLOSURE"], "yes")
        self.assertEqual(result["WPE_INSTALLED_ASSETS_STATUS"],
                         "copied_and_static_elf_checked")

    def test_injected_bundle_missing_direct_soname_blocks(self):
        self.add_strict_installed_assets()
        self.dynamics["libWPEInjectedBundle.so"] += (
            "0x01 (NEEDED) Shared library: [libinjectedonly.so.1]\\n")
        result = self.run_audit()
        self.assertIn("libWPEInjectedBundle.so:libinjectedonly.so.1",
                      result["WPE_MISSING_SONAMES"])
        self.assertEqual(result["WPE_RUNTIME_CLOSURE"], "BLOCKED")

    def test_injected_bundle_stage_only_dependency_blocks(self):
        self.add_strict_installed_assets()
        self.create(self.stage / "usr/lib/libprivateinjected.so.1")
        self.dynamics["libWPEInjectedBundle.so"] += (
            "0x01 (NEEDED) Shared library: [libprivateinjected.so.1]\\n")
        result = self.run_audit()
        self.assertEqual(result["WPE_RUNTIME_CLOSURE"], "BLOCKED")
        self.assertIn("libWPEInjectedBundle.so:libprivateinjected.so.1",
                      result["WPE_STAGE_ONLY_DEPENDENCIES"])

    def test_reject_strict_assets_incomplete_or_misreported(self):
        module, resource = self.add_strict_installed_assets()
        resource.unlink()
        with self.assertRaisesRegex(ValueError, "PARTIAL_WPE_INJECTED_ASSETS"):
            self.run_audit()
        resource.write_bytes(b"restored")
        module.unlink()
        with self.assertRaisesRegex(ValueError, "PARTIAL_WPE_INJECTED_ASSETS"):
            self.run_audit()
        self.create(module)
        (self.runtime / "BUILD-REPORT.txt").write_text(
            "GPU_PROCESS_PROFILE=disabled_verified_wayland\\n"
            "WPE_INSTALLED_ASSETS_PROFILE=strict\\n"
            "WPE_INSTALLED_ASSETS_STATUS=not_installed\\n")
        with self.assertRaisesRegex(ValueError, "STRICT_WPE_ASSETS_NOT_REPORTED"):
            self.run_audit()

    def test_reject_injected_bundle_symlink_and_drift(self):
        module, resource = self.add_strict_installed_assets()
        module.unlink()
        module.symlink_to("/etc/passwd")
        with self.assertRaisesRegex(ValueError, "UNSAFE_WPE_INJECTED_ASSETS"):
            self.run_audit()
        module.unlink()
        self.create(module)
        (self.runtime / "BUILD-REPORT.txt").write_text(
            "GPU_PROCESS_PROFILE=disabled_verified_wayland\\n"
            "WPE_INSTALLED_ASSETS_PROFILE=strict\\n"
            "WPE_INSTALLED_ASSETS_PROFILE=optional\\n"
            "WPE_INSTALLED_ASSETS_STATUS=copied_and_static_elf_checked\\n")
        with self.assertRaisesRegex(ValueError, "CONFLICTING_WPE_ASSET_REPORT"):
            self.run_audit()

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
        self.assertEqual(result["WPE_RUNTIME_CLOSURE"], "BLOCKED")
        self.assertEqual(result["WPE_STAGE_ONLY_COUNTS_AS_BLOCKER"], "yes")
        self.assertEqual(result["R36H_INSTALLABLE"], "no")


    def test_reject_foreign_loader_path(self):
        self.interps["WPEWebProcess"] = (
            "      [Requesting program interpreter: /lib64/ld-linux-x86-64.so.2]\\n")
        result = self.run_audit()
        self.assertEqual(result["WPE_RUNTIME_CLOSURE"], "BLOCKED")
        self.assertIn("FOREIGN_PT_INTERP:WPEWebProcess:/lib64/ld-linux-x86-64.so.2",
                      result["WPE_ABI_FINDINGS"])

    def test_reject_missing_and_unsafe_loader(self):
        loader = self.sysroot / "lib/ld-linux-aarch64.so.1"
        loader.unlink()
        result = self.run_audit()
        self.assertIn("MISSING_SYSROOT_PT_INTERP:WPEWebProcess:/lib/ld-linux-aarch64.so.1",
                      result["WPE_ABI_FINDINGS"])
        self.assertEqual(result["WPE_RUNTIME_CLOSURE"], "BLOCKED")
        loader.symlink_to("/etc/passwd")
        self.assertIn("MISSING_SYSROOT_PT_INTERP:WPENetworkProcess:/lib/ld-linux-aarch64.so.1",
                      self.run_audit()["WPE_ABI_FINDINGS"])

    def test_reject_wrong_architecture_loader(self):
        self.headers["ld-linux-aarch64.so.1"] = ARM64.replace("AArch64", "X86-64")
        self.assertIn("WRONG_ARCH_PT_INTERP:WPENetworkProcess:/lib/ld-linux-aarch64.so.1",
                      self.run_audit()["WPE_ABI_FINDINGS"])

    def test_reject_dynamic_helper_without_interpreter(self):
        self.interps["WPEWebProcess"] = ""
        self.assertIn("MISSING_DYNAMIC_PT_INTERP:WPEWebProcess",
                      self.run_audit()["WPE_ABI_FINDINGS"])
        self.assertEqual(self.run_audit()["WPE_RUNTIME_CLOSURE"], "BLOCKED")

    def test_accept_statically_linked_helper_without_interpreter(self):
        self.interps["WPENetworkProcess"] = ""
        self.dynamics["WPENetworkProcess"] = ""
        result = self.run_audit()
        self.assertEqual(result["WPE_RUNTIME_CLOSURE"], "SDK_STATIC_CANDIDATES_ONLY")
        self.assertEqual(result["WPE_PT_INTERP_CHECKS"], 1)

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
