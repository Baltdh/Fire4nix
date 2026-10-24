#!/usr/bin/env python3
"""Exercise real readelf output for versioned symbols without executing an ELF."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
def load(name, file):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'scripts' / file)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

closure = load('closure_versioned', 'audit-wpe-runtime-closure.py')
bundler = load('bundler_versioned', 'bundle-rocknix-wpe-sdk-deps.py')

class VersionedAtomicTests(unittest.TestCase):
    def test_real_versioned_exports_are_not_truncated(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            target = root / 'aarch64-rocknix-linux-gnu/lib64/libatomic.so.1'
            target.parent.mkdir(parents=True)
            src = root / 'atomic.c'
            src.write_text('int load16(void) __asm__("__atomic_load_16");\n'
                           'int load16(void) { return 0; }\n'
                           'int store16(void) __asm__("__atomic_store_16");\n'
                           'int store16(void) { return 0; }\n')
            version = root / 'atomic.map'
            version.write_text('LIBATOMIC_1.0 { global: __atomic_load_16; __atomic_store_16; local: *; };\n')
            subprocess.run(['cc', '-shared', '-fPIC', str(src),
                            '-Wl,-soname,libatomic.so.1', '-Wl,--version-script=' + str(version),
                            '-o', str(target)], check=True, capture_output=True)
            # Only skip ARM64 metadata for this HOST ELF fixture. The production
            # validator retains all architecture/SONAME/version/path guards.
            with mock.patch.object(bundler, 'validated_stage_elf'):
                self.assertEqual(bundler.audited_toolchain_libatomic(closure, root), target)
            self.assertIn('__atomic_load_16@@LIBATOMIC_1.0', closure.readelf('--dyn-syms', target))

if __name__ == '__main__':
    unittest.main()
