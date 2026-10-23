import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('portable', Path(__file__).resolve().parents[2] / 'scripts/prepare-portable-sdk-rpaths.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

class PortableRpaths(unittest.TestCase):
    def test_remove_only_standard_system_directories(self):
        self.assertTrue(mod.removable([('RUNPATH', '/usr/lib:/lib64')]))
        self.assertFalse(mod.removable([]))
        self.assertFalse(mod.removable([('RPATH', '$ORIGIN:$ORIGIN/private')]))

    def test_reject_unexpected_empty_mixed_and_traversal(self):
        for value in ('', '/usr/lib:', '/home/runner/build', '$ORIGIN/..', '$ORIGIN/a/../b', '/usr/lib:$ORIGIN'):
            with self.subTest(value=value), self.assertRaises(ValueError):
                mod.removable([('RUNPATH', value)])

    def test_copy_preserves_source_and_checks_abi(self):
        with tempfile.TemporaryDirectory() as tmp:
            src, dst = Path(tmp)/'src', Path(tmp)/'dst'
            src.mkdir()
            lib = src/'libtest.so.1'
            lib.write_bytes(b'\x7fELForiginal')
            before = dict(runpaths=[('RUNPATH', '/usr/lib')], dynamic=[('SONAME', 'libtest.so.1')], glibc=[(2, 17)])
            after = dict(before, runpaths=[])
            def modify(*cmd):
                Path(cmd[-1]).write_bytes(b'\x7fELFpatched')
            with patch.object(mod.audit, 'details', side_effect=[before, after]), patch.object(mod.audit, 'run', side_effect=modify):
                mod.prepare(src, dst)
            self.assertEqual(lib.read_bytes(), b'\x7fELForiginal')
            self.assertEqual((dst/lib.name).read_bytes(), b'\x7fELFpatched')

    def test_abi_change_blocks(self):
        with tempfile.TemporaryDirectory() as tmp:
            src, dst = Path(tmp)/'src', Path(tmp)/'dst'
            src.mkdir()
            (src/'libtest.so.1').write_bytes(b'\x7fELFfixture')
            before = dict(runpaths=[('RPATH', '/usr/lib')], dynamic=[('NEEDED', 'libc.so.6')], glibc=[])
            after = dict(before, runpaths=[], dynamic=[])
            with patch.object(mod.audit, 'details', side_effect=[before, after]), patch.object(mod.audit, 'run'), self.assertRaisesRegex(ValueError, 'ABI_METADATA_CHANGED'):
                mod.prepare(src, dst)

if __name__ == '__main__':
    unittest.main()
