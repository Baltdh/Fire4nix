#!/usr/bin/env python3
"""Protect genuine GCC15 libatomic16 exports from truncated readelf output."""
from __future__ import annotations
import importlib.util
from pathlib import Path
from types import SimpleNamespace
from unittest import TestCase, main, mock

ROOT = Path(__file__).resolve().parents[2]
def load(name: str, filename: str):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / filename)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

bundle = load("fire4nix_libatomic_bundle", "bundle-rocknix-wpe-sdk-deps.py")
closure = load("fire4nix_elf_closure", "audit-wpe-runtime-closure.py")
LIBATOMIC = """Symbol table '.dynsym' contains 100 entries:
    75: 00000000000037e0    79 IFUNC   GLOBAL DEFAULT   13 __atomic_load_16@@LIBATOMIC_1.0
    49: 0000000000003860    79 IFUNC   GLOBAL DEFAULT   13 __atomic_store_16@@LIBATOMIC_1.0
"""

class Atomic16ExportTests(TestCase):
    def test_full_128bit_exports(self):
        self.assertTrue(bundle.libatomic_exported(LIBATOMIC, "__atomic_load_16"))
        self.assertTrue(bundle.libatomic_exported(LIBATOMIC, "__atomic_store_16"))

    def test_no_substring_acceptance(self):
        for suffix in ("_fake", "32", "@LIBATOMIC_1.0", "@@EVIL_1.0"):
            bad = LIBATOMIC.replace("__atomic_load_16@@LIBATOMIC_1.0",
                                    "__atomic_load_16" + suffix)
            with self.subTest(suffix=suffix):
                self.assertFalse(bundle.libatomic_exported(bad, "__atomic_load_16"))

    def test_nonexports_rejected(self):
        for fragment in (
            "    75: 0000 0 IFUNC GLOBAL DEFAULT UND __atomic_load_16@@LIBATOMIC_1.0\n",
            "    75: 0000 0 IFUNC LOCAL DEFAULT 12 __atomic_load_16@@LIBATOMIC_1.0\n",
            "    75: 0000 0 IFUNC GLOBAL DEFAULT 12 _[...]@@LIBATOMIC_1.0\n",
        ):
            with self.subTest(fragment=fragment):
                self.assertFalse(bundle.libatomic_exported(fragment, "__atomic_load_16"))

    def test_readelf_uses_wide_for_dynamic_symbols(self):
        with mock.patch.object(closure.subprocess, "run") as runner:
            runner.return_value = SimpleNamespace(stdout=LIBATOMIC)
            text = closure.readelf("--dyn-syms", Path("/private/target/libatomic.so.1"))
        self.assertIn("__atomic_load_16", text)
        cmd = runner.call_args.args[0]
        self.assertEqual(cmd, ["readelf", "--wide", "--dyn-syms",
                               "/private/target/libatomic.so.1"])
        with mock.patch.object(closure.subprocess, "run") as runner:
            runner.return_value = SimpleNamespace(stdout="header")
            closure.readelf("-h", Path("/private/target/libatomic.so.1"))
        self.assertEqual(runner.call_args.args[0],
                         ["readelf", "-h", "/private/target/libatomic.so.1"])

    def test_missing_provider_never_accepted(self):
        self.assertFalse(bundle.libatomic_exported("", "__atomic_load_16"))
        self.assertFalse(bundle.libatomic_exported(LIBATOMIC, "__not_required"))

if __name__ == "__main__":
    main(verbosity=2)
