#!/usr/bin/env python3
"""Unit-test WPE WebKit + Web/Network process artifact inspection without ARM execution."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/audit-real-fourcc-wpe-artifacts.py"
spec = importlib.util.spec_from_file_location("audit_fourcc_evidence", SCRIPT)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

HEADER = ("Class: ELF64\nData: 2's complement, little endian\n"
          "Machine: AArch64\nType: DYN (Shared object file)\n")
VERSION = "Name: GLIBC_2.41"
INTERP = "      [Requesting program interpreter: /lib/ld-linux-aarch64.so.1]\\n"
SYM = "12: 0 40 FUNC GLOBAL DEFAULT 15 webkit_web_view_get_wpe_view"
DYN = ("(SONAME) Library soname: [libWPEWebKit-2.0.so.1]\n"
       "(NEEDED) Shared library: [libc.so.6]\n")


class RealWPEEvidenceTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.stage = self.root / "download/compiled-target-evidence"
        self.stage.mkdir(parents=True)
        for name in m.NAMES:
            (self.stage / name).write_bytes(b"\x7fELF" + b"\x00" * 256)

    def fake_read(self, flag, path):
        return {"-h": HEADER, "-d": DYN,
                "-V": VERSION,
                "-l": INTERP,
                "--dyn-syms": SYM if path.name.startswith("libWPE") else ""}[flag]

    def test_complete_files_never_claim_installable(self):
        content, passed = m.evidence(self.root, "success", self.fake_read)
        self.assertTrue(passed)
        self.assertIn("WPE_LINKED_AND_PROCESSES_STATUS=PASS_STATIC_ONLY_NOT_DEVICE_ABI", content)
        self.assertIn("R36H_INSTALLABLE=no", content)
        self.assertIn("R36H_PHYSICAL_TEST_COMPLETED=no", content)

    def test_missing_network_process_fails_closed(self):
        (self.stage / "WPENetworkProcess").unlink()
        content, passed = m.evidence(self.root, "success", self.fake_read)
        self.assertFalse(passed)
        self.assertIn("WPENetworkProcess:MISSING", content)

    def test_failure_never_becomes_success_even_with_good_elves(self):
        content, passed = m.evidence(self.root, "failure", self.fake_read)
        self.assertFalse(passed)
        self.assertIn("SOURCE_BUILD_CONCLUSION=failure", content)

    def test_second_output_folder_is_ambiguous(self):
        other = self.root / "another/compiled-target-evidence"
        other.mkdir(parents=True)
        content, passed = m.evidence(self.root, "success", self.fake_read)
        self.assertFalse(passed)
        self.assertIn("WPE_EVIDENCE_DIR_COUNT=2", content)


    def test_reject_foreign_interpreter_even_with_aarch64_header(self):
        def bad_loader(flag, path):
            if flag == "-l" and path.name == "WPEWebProcess":
                return "      [Requesting program interpreter: /lib64/ld-linux-x86-64.so.2]\\n"
            return self.fake_read(flag, path)
        content, passed = m.evidence(self.root, "success", bad_loader)
        self.assertFalse(passed)
        self.assertIn("FOREIGN_PT_INTERP:/lib64/ld-linux-x86-64.so.2", content)

    def test_reject_dynamic_process_missing_loader(self):
        def no_loader(flag, path):
            if flag == "-l" and path.name == "WPENetworkProcess":
                return ""
            return self.fake_read(flag, path)
        content, passed = m.evidence(self.root, "success", no_loader)
        self.assertFalse(passed)
        self.assertIn("WPENetworkProcess:MISSING_DYNAMIC_PT_INTERP", content)

    def test_accept_static_process_without_loader(self):
        def static_process(flag, path):
            if path.name == "WPENetworkProcess":
                if flag == "-l":
                    return ""
                if flag == "-d":
                    return ""
            return self.fake_read(flag, path)
        content, passed = m.evidence(self.root, "success", static_process)
        self.assertTrue(passed)
        self.assertIn("WPE_ARTIFACT_WPENetworkProcess=PASS_STATIC_AARCH64", content)

    def test_foreign_architecture(self):
        def bad_arch(flag, path):
            val = self.fake_read(flag, path)
            return val.replace("AArch64", "X86-64") if flag == "-h" else val
        content, passed = m.evidence(self.root, "success", bad_arch)
        self.assertFalse(passed)
        self.assertIn("WRONG_MACHINE", content)

    def test_ci_runpath_and_new_glibc(self):
        def bad(flag, path):
            v = self.fake_read(flag, path)
            if flag == "-d":
                v += "(RUNPATH) Library runpath: [/home/runner/work/Fire4nix]\n"
            if flag == "-V":
                v += "\nName: GLIBC_2.42"
            return v
        content, passed = m.evidence(self.root, "success", bad)
        self.assertFalse(passed)
        self.assertIn("UNSAFE_RUNPATH", content)
        self.assertIn("GLIBC_ABOVE_2_41", content)

    def test_no_required_wpe_export(self):
        def missing_export(flag, path):
            return "" if flag == "--dyn-syms" else self.fake_read(flag, path)
        content, passed = m.evidence(self.root, "success", missing_export)
        self.assertFalse(passed)
        self.assertIn("MISSING_WPE_PLATFORM_ENTRYPOINT", content)


    def test_unresolved_gcc15_outlined_atomics_block_shared_webkit(self):
        def unresolved(flag, path):
            value = self.fake_read(flag, path)
            if flag == "--dyn-syms" and path.name == "libWPEWebKit-2.0.so.1":
                return value + "\n 12: 0 0 FUNC GLOBAL DEFAULT UND __aarch64_ldadd4_acq_rel"
            return value
        content, passed = m.evidence(self.root, "success", unresolved)
        self.assertFalse(passed)
        self.assertIn("UNDEFINED_GCC15_OUTLINED_ATOMIC:__aarch64_ldadd4_acq_rel",
                      content)

    def test_outlined_atomics_block_real_web_and_network_processes(self):
        for name, helper in (("WPEWebProcess", "__aarch64_cas4_acq_rel"),
                             ("WPENetworkProcess", "__aarch64_swp4_acq_rel")):
            with self.subTest(name=name):
                def unresolved(flag, path):
                    value = self.fake_read(flag, path)
                    if flag == "--dyn-syms" and path.name == name:
                        return value + "\n 12: 0 0 FUNC GLOBAL DEFAULT UND " + helper
                    return value
                content, passed = m.evidence(self.root, "success", unresolved)
                self.assertFalse(passed)
                self.assertIn(name + ":UNDEFINED_GCC15_OUTLINED_ATOMIC:" + helper, content)

    def test_defined_aarch64_helper_and_lse_probe_are_not_undefined(self):
        def defined(flag, path):
            value = self.fake_read(flag, path)
            if flag == "--dyn-syms" and path.name == "WPEWebProcess":
                return (value
                        + "\n 12: 0 0 FUNC GLOBAL DEFAULT 14 __aarch64_ldadd4_acq_rel"
                        + "\n 13: 0 0 FUNC GLOBAL DEFAULT UND __aarch64_have_lse_atomics")
            return value
        content, passed = m.evidence(self.root, "success", defined)
        self.assertTrue(passed)
        self.assertNotIn("UNDEFINED_GCC15_OUTLINED_ATOMIC", content)

    def test_gstreamer_symbol_forbidden(self):
        def bad_gst(flag, path):
            if flag == "--dyn-syms":
                return self.fake_read(flag, path) + "\n1: 0 0 OBJECT GLOBAL DEFAULT UND GST_CAT_DEFAULT"
            return self.fake_read(flag, path)
        content, passed = m.evidence(self.root, "success", bad_gst)
        self.assertFalse(passed)
        self.assertIn("GST_CAT_DEFAULT_UNRESOLVED", content)

    def test_symlink_component_rejected(self):
        (self.stage / "WPEWebProcess").unlink()
        (self.stage / "WPEWebProcess").symlink_to(self.stage / "WPENetworkProcess")
        content, passed = m.evidence(self.root, "success", self.fake_read)
        self.assertFalse(passed)
        self.assertIn("WPEWebProcess:MISSING", content)


if __name__ == "__main__":
    unittest.main(verbosity=2)
