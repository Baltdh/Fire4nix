import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]

class PortableMktemp(unittest.TestCase):
    def test_launcher_and_testkit_accept_trailing_x_only_mktemp(self):
        with tempfile.TemporaryDirectory() as tmp:
            t=Path(tmp);(t/'tools').mkdir();(t/'Fire4Nix/bin').mkdir(parents=True)
            wrapper=t/'tools/mktemp'
            wrapper.write_text('#!/bin/sh\ncase "$1" in *XXXXXX) exec '+shutil.which('mktemp')+' "$@" ;; *) echo "mktemp: Invalid argument" >&2; exit 1 ;; esac\n')
            wrapper.chmod(0o755)
            binary=t/'Fire4Nix/bin/fire4nix-native-aarch64'
            binary.write_text('#!/bin/sh\nexit 0\n');binary.chmod(0o755)
            shutil.copy(ROOT/'installer/Fire4Nix-Teste.sh',t)
            # Keep this host fixture from writing the physical-device log path.
            launcher=(ROOT/'installer/Fire4Nix-Iniciar.sh').read_text().replace('/storage/',str(t/'device')+'/').replace('[ -w /storage ]','[ -w '+str(t/'device')+' ]')
            (t/'Fire4Nix/Fire4Nix-Iniciar.sh').write_text(launcher)
            env=dict(os.environ,PATH=str(t/'tools')+':'+os.environ['PATH'],FIRE4NIX_TEST_REPORT_DIR=str(t/'reports'),FIRE4NIX_LOG_DIR=str(t/'logs'))
            for _ in range(2):
                subprocess.run(['sh',str(t/'Fire4Nix-Teste.sh'),'--collect'],env=env,check=True,capture_output=True)
                subprocess.run(['sh',str(t/'Fire4Nix/Fire4Nix-Iniciar.sh'),'--selftest'],env=env,check=True,capture_output=True)
            self.assertTrue((t/'reports/Fire4Nix-Ultimo-Teste.txt').is_file())
            self.assertEqual(len(list((t/'logs').glob('Fire4Nix-*-log-*'))),2)
            self.assertEqual(len(list((t/'reports').glob('Fire4Nix-Teste-101-txt-*'))),2)

if __name__=='__main__': unittest.main()
