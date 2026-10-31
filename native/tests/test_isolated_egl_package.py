#!/usr/bin/env python3
"""Regression: the isolated R36H EGL runner ships with its required probe."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/package-first-r36h-ports-candidate.py"
SPEC = importlib.util.spec_from_file_location("fire4nix_ports_packager", SCRIPT)
packager = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(packager)


class IsolatedEGLPackageTests(unittest.TestCase):
    def test_runner_and_probe_are_both_required_and_packaged_at_root(self):
        with tempfile.TemporaryDirectory() as tmp:
            installer = Path(tmp) / "installer"
            installer.mkdir()
            for name in (
                "Fire4Nix-Direto.sh", "Fire4Nix-Grafico-Resgate.sh",
                "Executar-Teste-Isolado.sh", "Fire4Nix-EGL-R36H.py",
                "Habilitar-Teste-Ports.sh", "Fire4Nix-Teste.sh",
                "Diagnosticar-Fire4Nix.sh", "Fire4Nix-Iniciar.sh",
                "Fire4Nix-Inspecionar-ELF.sh",
            ):
                (installer / name).write_text("# fixture: " + name + "\n")
            for folder in ("www", "config"):
                (installer / folder).mkdir()
                (installer / folder / "fixture.txt").write_text("fixture\n")
            entries = packager.source_files(installer)
            by_destination = {dest: source for source, dest, executable in entries}
            self.assertIn("Executar-Teste-Isolado.sh", by_destination)
            self.assertIn("Fire4Nix-EGL-R36H.py", by_destination)
            self.assertEqual(
                by_destination["Fire4Nix-EGL-R36H.py"].read_bytes(),
                (installer / "Fire4Nix-EGL-R36H.py").read_bytes(),
            )

    def test_missing_probe_blocks_package(self):
        with tempfile.TemporaryDirectory() as tmp:
            installer = Path(tmp) / "installer"
            installer.mkdir()
            for name in (
                "Fire4Nix-Direto.sh", "Fire4Nix-Grafico-Resgate.sh",
                "Executar-Teste-Isolado.sh",
            ):
                (installer / name).write_text("fixture\n")
            with self.assertRaisesRegex(
                ValueError,
                "MISSING_ISOLATED_TEST_COMPONENT:Fire4Nix-EGL-R36H.py",
            ):
                packager.source_files(installer)


if __name__ == "__main__":
    unittest.main(verbosity=2)
