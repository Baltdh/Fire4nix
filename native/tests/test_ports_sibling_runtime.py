"""Test the actual Ports test-kit wrappers beside the standard Fire4Nix folder."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]

class SiblingRuntime(unittest.TestCase):
    def test_generated_graphics_wrapper_uses_sibling_runtime_and_diagnostic(self):
        with tempfile.TemporaryDirectory(prefix='ports with spaces ') as tmp:
            base=Path(tmp); ports=base/'roms/ports'; app=ports/'Fire4Nix'
            for name in ('bin/fire4nix-native-aarch64','www/inicio.html',
                         'www/primeiro-teste.html','config/fire4nix.gptk',
                         'runtime/lib/libWPEWebKit-2.0.so.1'):
                f=app/name;f.parent.mkdir(parents=True,exist_ok=True);f.write_text('fixture')
            (app/'bin/fire4nix-native-aarch64').write_text('#!/bin/sh\nexit 0\n')
            (app/'bin/fire4nix-native-aarch64').chmod(0o755)
            (app/'Fire4Nix-Iniciar.sh').write_text('#!/bin/sh\necho TEST_PAGE="$2"\nexit 70\n')
            for name in ('Habilitar-Teste-Ports.sh','Fire4Nix-Teste.sh'):
                shutil.copy(ROOT/'installer'/name,ports/name)
            (ports/'Diagnosticar-Fire4Nix.sh').write_text('#!/bin/sh\nprintf "WPE_runtime_source=%s\\n" "$FIRE4NIX_DIAGNOSTIC_RUNTIME" > "$FIRE4NIX_DIAGNOSTIC_OUT"\n')
            env=dict(os.environ,FIRE4NIX_ROMS=str(base/'roms'),FIRE4NIX_TEST_REPORT_DIR=str(base/'reports'))
            env.pop('FIRE4NIX_DIAGNOSTIC_RUNTIME',None)
            subprocess.run(['sh',str(ports/'Habilitar-Teste-Ports.sh')],env=env,check=True,capture_output=True)
            p=subprocess.run(['sh',str(ports/'Fire4Nix-Grafico-101.sh')],env=env,cwd='/',capture_output=True,text=True)
            self.assertEqual(p.returncode,70,p.stdout+p.stderr)
            report=(base/'reports/Fire4Nix-Ultimo-Teste.txt').read_text()
            self.assertIn('installed_runtime_root='+str(app),report)
            self.assertIn('WPE_runtime_source='+str(app/'runtime'),report)
            self.assertIn('TEST_PAGE=file://'+str(app/'www/primeiro-teste.html'),report)
            self.assertFalse((ports/'.Fire4Nix-Teste-101/Fire4Nix/runtime').exists())

if __name__=='__main__': unittest.main()
