import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'scripts/validate_wpe_startup.sh'

class StartupValidationTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / 'scripts').mkdir()
        shutil.copyfile(SCRIPT, self.root / 'scripts/validate_wpe_startup.sh')
        (self.root / 'scripts/fire4nix_env.sh').write_text('''fire4nix_bootstrap_environment() { return 0; }
fire4nix_export_wpe_common_env() { export WPE_PLATFORM=wayland; }
fire4nix_wpe_runtime_env() { return 0; }
fire4nix_wpe_platform_binary() { printf '%s/bin/launcher' "$APP_DIR"; }
fire4nix_wayland_socket_available() { [ "${TEST_SOCKET:-yes}" = yes ]; }
fire4nix_wayland_socket_path() { echo /test/socket; }
''')
        (self.root / 'bin').mkdir()
        self.launcher = self.root / 'bin/launcher'
        self.launcher.write_bytes(b'\x7fELF\x02\x01\x01'+bytes(9)+struct.pack('<HHIQQQIHHHHHH', 3,183,1,0,0,0,0,64,0,0,0,0,0))
        self.launcher.chmod(0o755)
        (self.root / 'runtime/aarch64/lib').mkdir(parents=True)
        procs = self.root / 'runtime/aarch64/libexec/wpe-webkit-2.0'
        procs.mkdir(parents=True)
        for name in ('WPEWebProcess','WPENetworkProcess','WPEGPUProcess'):
            shutil.copy(self.launcher, procs / name)

    def run_check(self, **extra):
        env = dict(os.environ, FIRE4NIX_CONFIG_DIR=str(self.root/'config'), FIRE4NIX_STARTUP_REPORT=str(self.root/'report.log'), **extra)
        result = subprocess.run(['bash',str(self.root/'scripts/validate_wpe_startup.sh')], env=env, capture_output=True, text=True)
        return result.returncode, (self.root/'report.log').read_text()

    def test_valid_layout_passes(self):
        self.assertEqual(self.run_check()[0], 0)

    def test_missing_socket_fails(self):
        code, report = self.run_check(TEST_SOCKET='no')
        self.assertEqual(code,1)
        self.assertIn('Wayland socket unavailable',report)

    def test_non_executable_launcher_fails(self):
        self.launcher.chmod(0o644)
        self.assertEqual(self.run_check()[0],1)

    def test_invalid_launcher_fails(self):
        self.launcher.write_text('#!/bin/sh\n')
        self.assertEqual(self.run_check()[0],1)

    def test_missing_runtime_fails(self):
        shutil.rmtree(self.root/'runtime')
        self.assertEqual(self.run_check()[0],1)

if __name__ == '__main__':
    unittest.main()
