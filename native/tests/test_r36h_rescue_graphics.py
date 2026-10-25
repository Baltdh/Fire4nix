#!/usr/bin/env python3
"""No GPU access or WPE execution: mock R36H graphical recovery decisions."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SRC = Path(__file__).resolve().parents[2] / 'installer/Fire4Nix-Grafico-Resgate.sh'

class RescueTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory(prefix='fire4nix rescue paths with spaces ')
        self.addCleanup(tmp.cleanup)
        self.home = Path(tmp.name)
        self.app = self.home / 'Fire4Nix'
        for name in ('bin/fire4nix-native-aarch64', 'runtime/lib/libWPEWebKit-2.0.so.1',
                     'runtime/libexec/wpe-webkit-2.0/WPEWebProcess',
                     'runtime/libexec/wpe-webkit-2.0/WPENetworkProcess',
                     'www/primeiro-teste.html'):
            p = self.app / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text('mock\n')
        shutil.copyfile(SRC, self.home / SRC.name)
        (self.app / 'Fire4Nix-Iniciar.sh').write_text("""#!/bin/sh
echo mock_url="$3"
echo mock_mode=$1 cpu=${WEBKIT_SKIA_ENABLE_CPU_RENDERING:-unset} mali=${MALI_DEFAULT_DISPLAY:-unset} fallback=${FIRE4NIX_WPE_DEFAULT_EGL:-unset}
case "$1" in --check-library|--check-platform) exit 0;; esac
if [ "$MOCK_NATIVE_ONLY" = 1 ] && [ "$WEBKIT_SKIA_ENABLE_CPU_RENDERING" = "" ]; then
    echo 'Could not create EGL display: no supported platform available' > "$FIRE4NIX_LOG_DIR/Fire4Nix-2026-log-ABCDEF"
    i=0
    while [ "$i" -lt 60 ]; do
        echo "noise-$i" >> "$FIRE4NIX_LOG_DIR/Fire4Nix-2026-log-ABCDEF"
        i=$((i+1))
    done
    tail -n 40 "$FIRE4NIX_LOG_DIR/Fire4Nix-2026-log-ABCDEF"
    exit "$MOCK_GPU_EXIT"
fi
case "${WEBKIT_SKIA_ENABLE_CPU_RENDERING:-}" in
  1) exit "${MOCK_CPU_EXIT:-0}";;
  *) if [ "${MOCK_EGL_ERROR:-0}" = 1 ]; then echo 'Could not create EGL display: no supported platform available'; fi
     exit "${MOCK_GPU_EXIT:-70}";;
esac
""")
    def launch(self, mode='--auto', gpu='70', cpu='0', **overrides):
        env = {**os.environ, 'MOCK_GPU_EXIT':gpu, 'MOCK_CPU_EXIT':cpu, **overrides}
        if 'MALI_DEFAULT_DISPLAY' not in overrides: env.pop('MALI_DEFAULT_DISPLAY', None)
        if 'FIRE4NIX_WPE_DEFAULT_EGL' not in overrides: env.pop('FIRE4NIX_WPE_DEFAULT_EGL', None)
        p = subprocess.run(['sh', str(self.home / SRC.name), mode], cwd='/', env=env,
                           text=True, capture_output=True, timeout=10)
        report = (self.app / 'logs/Fire4Nix-Grafico-Resgate-ultimo.txt')
        return p, report.read_text() if report.is_file() else ''
    def test_cpu_recovery_and_no_frame_claim(self):
        p, log = self.launch()
        self.assertEqual(p.returncode, 0)
        self.assertIn('mock_mode=--smoke cpu=unset mali=wayland fallback=1', log)
        self.assertIn('mock_mode=--smoke cpu=1 mali=wayland fallback=1', log)
        self.assertIn('first_frame_verified=no', log)
        self.assertIn('initial_classification=webprocess_terminated', log)
    def test_gpu_exit_statuses_recover(self):
        for code in ('70','71','124','134','139'):
            with self.subTest(code=code):
                p, log = self.launch(gpu=code)
                self.assertEqual(p.returncode, 0)
                self.assertIn('trial=software native_flag=--smoke', log)
    def test_preflight_and_load_errors_do_not_recover(self):
        for code in ('3','69','126','127'):
            with self.subTest(code=code):
                p, log = self.launch(gpu=code)
                self.assertEqual(p.returncode, int(code))
                self.assertNotIn('trial=software native_flag=', log)
    def test_signature_recovers_other_error(self):
        p, log = self.launch(gpu='5', MOCK_EGL_ERROR='1')
        self.assertEqual(p.returncode, 0)
        self.assertIn('graphics_signature_in_log', log)
    def test_signature_is_scoped_to_single_attempt(self):
        p, log = self.launch(gpu='5', cpu='6', MOCK_EGL_ERROR='1')
        self.assertEqual(p.returncode, 6)
        self.assertIn('final_classification=other_process_error', log)
    def test_ordinary_other_error_does_not_recover(self):
        p, log = self.launch(gpu='5')
        self.assertEqual(p.returncode, 5)
        self.assertNotIn('trial=software native_flag=', log)
    def test_preserve_explicit_egl_and_mali_overrides(self):
        p, log = self.launch(gpu='0', MALI_DEFAULT_DISPLAY='x11', FIRE4NIX_WPE_DEFAULT_EGL='0')
        self.assertEqual(p.returncode, 0)
        self.assertIn('mali=x11 fallback=0', log)
    def test_recovery_failure_returned(self):
        p, log = self.launch(gpu='70', cpu='139')
        self.assertEqual(p.returncode, 139)
        self.assertIn('final_classification=process_crashed_sigsegv', log)
    def test_live_auto_is_interactive(self):
        p, log = self.launch('--live-auto')
        self.assertEqual(p.returncode, 0)
        self.assertIn('trial=normal native_flag=--open', log)
        self.assertIn('trial=software native_flag=--open', log)
    def test_diagnosis_is_only_abi_check(self):
        p, log = self.launch('--diagnose')
        self.assertEqual(p.returncode, 0)
        self.assertIn('mock_mode=--check-library', log)
        self.assertIn('mock_mode=--check-platform', log)
        self.assertNotIn('mock_mode=--smoke', log)
        self.assertIn('GRAPHICAL_HARDWARE_STATUS=UNVERIFIED', log)
    def test_escape_spaces_in_file_uri(self):
        p, log = self.launch(gpu='0')
        self.assertEqual(p.returncode, 0)
        self.assertIn('mock_url=file://', log)
        self.assertIn('fire4nix%20rescue%20paths%20with%20spaces', log)
        self.assertNotIn('mock_url=file://'+str(self.home), log)

    def test_recover_hidden_egl_error_from_complete_native_log(self):
        p, log = self.launch(gpu='5', cpu='0', MOCK_NATIVE_ONLY='1')
        self.assertEqual(p.returncode, 0)
        self.assertIn('native_log_captured=Fire4Nix-2026-log-ABCDEF', log)
        self.assertIn('initial_classification=graphics_signature_in_log', log)
        self.assertIn('trial=software native_flag=--smoke', log)
        self.assertIn('noise-59', log)

    def test_hidden_egl_error_not_reused_in_cpu_trial(self):
        p, log = self.launch(gpu='5', cpu='6', MOCK_NATIVE_ONLY='1')
        self.assertEqual(p.returncode, 6)
        self.assertIn('final_classification=other_process_error', log)

    def test_missing_runtime_prevents_execution(self):
        (self.app / 'runtime/libexec/wpe-webkit-2.0/WPEWebProcess').unlink()
        p, _ = self.launch()
        self.assertEqual(p.returncode,127)
        self.assertIn('BLOCKED_MISSING_PACKAGE', p.stderr)

if __name__ == '__main__':
    unittest.main(verbosity=2)
