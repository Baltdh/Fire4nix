#!/usr/bin/env python3
"""Host-only unit tests: never package unresolved GCC15 AArch64 atomic helper calls."""
import importlib.util
from pathlib import Path
from unittest import TestCase, main, mock

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/package-first-r36h-ports-candidate.py"
spec = importlib.util.spec_from_file_location("ports_gcc15_gate", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

HEADER = "Class: ELF64\nMachine: AArch64\nData: 2's complement, little endian\n"
DYNAMIC = ("(SONAME) Library soname: [libWPEWebKit-2.0.so.1]\n"
           "(NEEDED) Shared library: [libc.so.6]\n")
VERSIONS = "Name: GLIBC_2.41"
EXPORT = "12: 0 20 FUNC GLOBAL DEFAULT 16 webkit_web_view_get_wpe_view"
INTERP = "      [Requesting program interpreter: /lib/ld-linux-aarch64.so.1]\n"


class AtomicArchiveGateTests(TestCase):
    def readelf_fixture(self, sym_extra):
        def fake(flag, file):
            return {
                "-h": HEADER,
                "-d": DYNAMIC,
                "-V": VERSIONS,
                "--dyn-syms": EXPORT + sym_extra,
                "-l": INTERP,
            }[flag]
        return fake

    def test_undefined_linker_helpers_rejected_before_zip(self):
        cases = [
            ("libWPEWebKit-2.0.so.1", "__aarch64_ldadd8_acq_rel"),
            ("libWPEInjectedBundle.so", "__aarch64_cas4_acq_rel"),
            ("WPEWebProcess", "__aarch64_swp4_acq_rel"),
            ("WPENetworkProcess", "__aarch64_ldadd4_relax"),
            ("libANGLE.so.1", "__aarch64_ldclr4_relax"),
        ]
        for name, helper in cases:
            with self.subTest(name=name, helper=helper):
                syms = "\n 23: 0 0 FUNC GLOBAL DEFAULT UND " + helper + "\n"
                with mock.patch.object(module, "get_readelf", side_effect=self.readelf_fixture(syms)):
                    with self.assertRaisesRegex(ValueError, "UNDEFINED_GCC15_OUTLINED_ATOMIC"):
                        module.elf_check(Path("/synthetic/" + name))

    def test_defined_helper_is_not_rejected(self):
        sym = "\n 23: 0 0 FUNC GLOBAL DEFAULT 7 __aarch64_ldadd8_acq_rel\n"
        with mock.patch.object(module, "get_readelf", side_effect=self.readelf_fixture(sym)):
            module.elf_check(Path("/synthetic/libWPEWebKit-2.0.so.1"))

    def test_nonoutlined_probe_is_not_rejected(self):
        sym = "\n 23: 0 0 FUNC GLOBAL DEFAULT UND __aarch64_have_lse_atomics\n"
        with mock.patch.object(module, "get_readelf", side_effect=self.readelf_fixture(sym)):
            module.elf_check(Path("/synthetic/WPEWebProcess"))

    def test_existing_soname_guard_preserved(self):
        def bad(flag, file):
            value = self.readelf_fixture("")(flag, file)
            return value.replace("libWPEWebKit-2.0.so.1", "libInvalid.so.1") if flag == "-d" else value
        with mock.patch.object(module, "get_readelf", side_effect=bad):
            with self.assertRaisesRegex(ValueError, "WPE_SONAME_MISMATCH"):
                module.elf_check(Path("/synthetic/libWPEWebKit-2.0.so.1"))

    def test_native_input_loader_is_checked_before_rename(self):
        for interpreter in ("", "/lib/ld-musl-aarch64.so.1", "/build/ld-linux-aarch64.so.1"):
            with self.subTest(interpreter=interpreter):
                def bad(flag, file):
                    if flag == "-l":
                        return f"[Requesting program interpreter: {interpreter}]" if interpreter else ""
                    return self.readelf_fixture("")(flag, file)
                with mock.patch.object(module, "get_readelf", side_effect=bad):
                    with self.assertRaisesRegex(ValueError, "INVALID_PROGRAM_LOADER"):
                        module.elf_check(Path("/synthetic/fire4nix-native-086-aarch64"))

    def test_native_input_supported_loaders(self):
        for interpreter in ("/lib/ld-linux-aarch64.so.1", "/lib64/ld-linux-aarch64.so.1"):
            with self.subTest(interpreter=interpreter):
                def valid(flag, file):
                    if flag == "-l":
                        return f"[Requesting program interpreter: {interpreter}]"
                    return self.readelf_fixture("")(flag, file)
                with mock.patch.object(module, "get_readelf", side_effect=valid):
                    module.elf_check(Path("/synthetic/fire4nix-native-086-aarch64"))


if __name__ == "__main__":
    main(verbosity=2)
