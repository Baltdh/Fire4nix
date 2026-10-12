import sys
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import bundle_missing_dependencies as module

class BundleTest(unittest.TestCase):
    def test_protected_system_library_is_never_copied(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            report = {'missing': [{'library': 'libc.so.6'}], 'errors': [], 'incompatible_versions': []}
            with patch.object(module, 'audit', return_value=report):
                result = module.bundle(root / 'runtime', root, root)
            self.assertEqual(result['copied'], [])
            self.assertFalse((root / 'runtime/lib/libc.so.6').exists())

    def test_missing_library_is_copied_then_reaudited(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'usr/lib').mkdir(parents=True)
            (root / 'usr/lib/libextra.so.1').write_bytes(b'ELF fixture')
            initial = {'missing': [{'library': 'libextra.so.1'}], 'errors': [], 'incompatible_versions': []}
            final = {'missing': [], 'errors': [], 'incompatible_versions': []}
            with patch.object(module, 'audit', side_effect=[initial, final]) as audit, patch.object(module, 'inspect', return_value={'machine': 'AArch64', 'soname': ['libextra.so.1']}):
                result = module.bundle(root / 'runtime', root, root)
            self.assertEqual(audit.call_count, 2)
            self.assertEqual(len(result['copied']), 1)
            self.assertEqual((root / 'runtime/lib/libextra.so.1').read_bytes(), b'ELF fixture')

if __name__ == '__main__':
    unittest.main()
