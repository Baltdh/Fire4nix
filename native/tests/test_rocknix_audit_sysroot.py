#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / 'scripts/prepare-rocknix-audit-sysroot.py'
spec = importlib.util.spec_from_file_location('audit_sysroot', SCRIPT)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

class SysrootTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.src = self.root / 'original'
        self.out = self.root / 'copy'
        (self.src / 'usr/lib').mkdir(parents=True)
        (self.src / 'usr/lib/ld-linux-aarch64.so.1').write_bytes(b'loader-fixture-not-executed')
        (self.src / 'usr/lib/libtest.so.1').write_bytes(b'library-fixture')
        self.alias = self.src / 'usr/lib/libtest.so'
        self.alias.symlink_to(mod.ORIGINAL / 'usr/lib/libtest.so.1')

    def test_pinned_link_rebased_only_in_private_copy(self):
        original = self.alias.readlink()
        self.assertEqual(mod.prepare(self.src, self.out), 1)
        self.assertEqual(self.alias.readlink(), original)
        self.assertEqual((self.out / 'usr/lib/libtest.so').read_bytes(), b'library-fixture')
        self.assertEqual((self.out / 'lib/ld-linux-aarch64.so.1').read_bytes(),
                         (self.src / 'usr/lib/ld-linux-aarch64.so.1').read_bytes())
        self.assertFalse((self.src / 'lib').exists())

    def test_host_link_is_rejected(self):
        self.alias.unlink()
        self.alias.symlink_to('/etc/passwd')
        with self.assertRaisesRegex(ValueError, 'UNRECOGNIZED_ABSOLUTE'):
            mod.prepare(self.src, self.out)
        self.assertFalse(self.out.exists())

    def test_missing_pinned_target_is_rejected(self):
        (self.src / 'usr/lib/libtest.so.1').unlink()
        with self.assertRaisesRegex(ValueError, 'MISSING_PINNED'):
            mod.prepare(self.src, self.out)

    def test_relative_escape_is_rejected(self):
        external = self.root / 'external'
        external.write_bytes(b'outside')
        self.alias.unlink()
        self.alias.symlink_to('../../../external')
        with self.assertRaisesRegex(ValueError, 'ESCAPING_RELATIVE'):
            mod.prepare(self.src, self.out)

    def test_output_is_not_replaced(self):
        self.out.mkdir()
        with self.assertRaisesRegex(ValueError, 'EXISTING_SYSROOT_OUTPUT'):
            mod.prepare(self.src, self.out)

    def test_cannot_write_into_source(self):
        with self.assertRaisesRegex(ValueError, 'OVERLAPPING'):
            mod.prepare(self.src, self.src / 'copy')

if __name__ == '__main__':
    unittest.main()
