import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[2] / 'installer/Executar-Teste-Isolado.sh'


class IsolatedEntryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='isolated test # ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        shutil.copyfile(SOURCE, self.root / SOURCE.name)
        self.files = [
            'Fire4Nix/bin/fire4nix-native-aarch64',
            'Fire4Nix/runtime/libexec/wpe-webkit-2.0/WPEWebProcess',
            'Fire4Nix/runtime/libexec/wpe-webkit-2.0/WPENetworkProcess',
        ]
        for name in self.files:
            p = self.root / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text('not executed\n')
        rescue = self.root / 'Fire4Nix-Grafico-Resgate.sh'
        rescue.write_text('#!/bin/sh\nprintf "root=%s mode=%s locale=%s\\n" "$FIRE4NIX_ROOT" "$1" "$LC_ALL"\nexit 70\n')
        self.files.append(rescue.name)
        (self.root / 'PACOTE-SHA256SUMS.txt').write_text(''.join(
            hashlib.sha256((self.root / name).read_bytes()).hexdigest() + '  ' + name + '\n'
            for name in self.files))
        self.mockbin = self.root / 'mockbin'
        self.mockbin.mkdir()
        uname = self.mockbin / 'uname'
        uname.write_text('#!/bin/sh\necho aarch64\n')
        uname.chmod(0o755)

    def run_entry(self, *args):
        env = {**os.environ, 'PATH': str(self.mockbin) + ':' + os.environ['PATH'],
               'FIRE4NIX_ROOT': '/wrong/old/package'}
        return subprocess.run(['sh', str(self.root / SOURCE.name), *args],
                              cwd='/', env=env, text=True, capture_output=True, timeout=5)

    def test_uses_own_package_and_preserves_failure(self):
        p = self.run_entry('--normal')
        self.assertEqual(p.returncode, 70, p.stderr)
        self.assertIn('root=' + str(self.root / 'Fire4Nix'), p.stdout)
        self.assertIn('mode=--normal locale=C', p.stdout)
        self.assertTrue(os.access(self.root / self.files[0], os.X_OK))

    def test_corruption_blocks_before_launch(self):
        (self.root / self.files[0]).write_text('corrupted')
        p = self.run_entry()
        self.assertEqual(p.returncode, 65)
        self.assertNotIn('root=', p.stdout)
        self.assertFalse(os.access(self.root / self.files[0], os.X_OK))

    def test_missing_manifest_blocks(self):
        (self.root / 'PACOTE-SHA256SUMS.txt').unlink()
        self.assertEqual(self.run_entry().returncode, 127)

    def test_invalid_mode_blocks(self):
        self.assertEqual(self.run_entry('--typo').returncode, 2)

    def test_wrong_architecture_blocks(self):
        (self.mockbin / 'uname').write_text('#!/bin/sh\necho x86_64\n')
        self.assertEqual(self.run_entry().returncode, 126)


if __name__ == '__main__':
    unittest.main()
