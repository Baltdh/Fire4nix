#!/usr/bin/env python3
"""No GPU access or WPE execution: mock R36H graphical recovery decisions."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
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
echo mock_mode=$1 cpu=${WEBKIT_SKIA_ENABLE_CPU_RENDERING:-unset} mali=${MALI_DEFAULT_DISPLAY:-unset} fallback=${FIRE4NIX_WPE_DEFAULT_EGL:-unset}
case "$1" in --check-library|--check-platform) exit 0;; esac
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
    def test_interrupt_is_not_restarted_even_after_graphics_message(self):
        for code in ('130','137','143'):
            with self.subTest(code=code):
                p, log = self.launch(gpu=code, MOCK_EGL_ERROR='1')
                self.assertEqual(p.returncode,int(code))
                self.assertNotIn('trial=software native_flag=',log)

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
    def test_explicit_missing_root_never_falls_back(self):
        p, _ = self.launch(FIRE4NIX_ROOT=str(self.home / 'missing'))
        self.assertEqual(p.returncode, 127)
        self.assertIn('BLOCKED_MISSING_PACKAGE', p.stderr)

    def test_relative_root_becomes_absolute_page_uri(self):
        (self.app / 'Fire4Nix-Iniciar.sh').write_text('#!/bin/sh\nprintf "page=%s\\n" "$2"\nexit 0\n')
        relative = os.path.relpath(self.app, '/')
        p, log = self.launch(gpu='0', FIRE4NIX_ROOT=relative)
        self.assertEqual(p.returncode, 0)
        self.assertIn('page=file://' + str(self.app) + '/www/primeiro-teste.html', log)

    def test_sessions_keep_separate_logs(self):
        self.launch(gpu='0')
        self.launch(gpu='3')
        logs = sorted((self.app/'logs').glob('Fire4Nix-Grafico-Resgate-log-*'))
        self.assertEqual(len(logs), 2)
        self.assertEqual(sorted('FIRE4NIX_RESCUE_EXIT=0' in p.read_text() for p in logs), [False, True])

    def test_concurrent_sessions_do_not_mix_report_contents(self):
        (self.app / 'Fire4Nix-Iniciar.sh').write_text('#!/bin/sh\necho session=$MOCK_SESSION\nsleep 0.2\nexit "$MOCK_GPU_EXIT"\n')
        jobs=[]
        for session, code in (('first','0'),('second','3')):
            env={**os.environ,'MOCK_SESSION':session,'MOCK_GPU_EXIT':code}
            jobs.append(subprocess.Popen(['sh',str(self.home/SRC.name),'--normal'],
                        env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True))
        for job in jobs:
            job.communicate(timeout=10)
        self.assertEqual([j.returncode for j in jobs],[0,3])
        logs=list((self.app/'logs').glob('Fire4Nix-Grafico-Resgate-log-*'))
        self.assertEqual(len(logs),2)
        for log in logs:
            text=log.read_text()
            self.assertNotEqual('session=first' in text,'session=second' in text)
            self.assertEqual(text.count('FIRE4NIX_RESCUE_EXIT='),1)
        latest=(self.app/'logs/Fire4Nix-Grafico-Resgate-ultimo.txt').read_text()
        self.assertIn(latest,[p.read_text() for p in logs])

    def test_failed_diagnosis_is_not_reported_as_abi_success(self):
        (self.app / 'Fire4Nix-Iniciar.sh').write_text('#!/bin/sh\nexit 127\n')
        p, log = self.launch('--diagnose')
        self.assertEqual(p.returncode, 127)
        self.assertIn('final_classification=diagnostic_failed_missing_or_unexecutable_runtime', log)
        self.assertNotIn('final_classification=abi_only_no_frame_proof', log)

    def test_hung_smoke_has_external_timeout(self):
        (self.app / 'Fire4Nix-Iniciar.sh').write_text('#!/bin/sh\nexec sleep 3\n')
        start = time.monotonic()
        p, log = self.launch('--normal', FIRE4NIX_RESCUE_TIMEOUT='1')
        self.assertEqual(p.returncode, 124)
        self.assertLess(time.monotonic()-start, 2.5)
        self.assertIn('final_classification=page_load_timeout', log)

    def test_live_session_has_no_smoke_timeout(self):
        (self.app / 'Fire4Nix-Iniciar.sh').write_text('#!/bin/sh\nsleep 2\nexit 0\n')
        p, _ = self.launch('--live', FIRE4NIX_RESCUE_TIMEOUT='1')
        self.assertEqual(p.returncode, 0)

    def test_invalid_timeout_is_rejected_before_launch(self):
        for value in ('0', '-1', 'abc', '1.2', '999999999999999999999999'):
            with self.subTest(value=value):
                p, _ = self.launch(FIRE4NIX_RESCUE_TIMEOUT=value)
                self.assertEqual(p.returncode, 2)

    def test_missing_runtime_prevents_execution(self):
        (self.app / 'runtime/libexec/wpe-webkit-2.0/WPEWebProcess').unlink()
        p, _ = self.launch()
        self.assertEqual(p.returncode,127)
        self.assertIn('BLOCKED_MISSING_PACKAGE', p.stderr)

if __name__ == '__main__':
    unittest.main(verbosity=2)
