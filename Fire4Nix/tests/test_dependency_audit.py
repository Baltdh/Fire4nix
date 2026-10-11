import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("dependency_audit", Path(__file__).resolve().parents[1] / "scripts/audit_runtime_dependencies.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class DependencyAuditTest(unittest.TestCase):
    def test_launcher_dependencies_are_checked_alongside_runtime(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            runtime = base / "runtime"
            runtime.mkdir()
            library = runtime / "libWPE.so"
            launcher = base / "launcher"
            for file in (library, launcher):
                file.write_bytes(b"\x7fELF")
            def inspect(path):
                return {"path": str(path), "machine": "AArch64", "needed": ["libMissing.so"] if path == launcher else [], "soname": [], "symbol_versions": [], "interpreter": []}
            with patch.object(module, "inspect", side_effect=inspect):
                report = module.audit(runtime, extra_elfs=(launcher,))
            self.assertEqual(report["missing"], [{"binary": str(launcher), "library": "libMissing.so"}])
            self.assertEqual(len(report["elfs"]), 2)

    def test_missing_launcher_is_an_error(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            report = module.audit(root, extra_elfs=(root / "missing",))
            self.assertTrue(any("launcher must" in x for x in report["errors"]))

    def test_script_launcher_is_not_accepted(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            launcher = root / "launcher"
            launcher.write_text("#!/bin/sh\n")
            report = module.audit(root, extra_elfs=(launcher,))
            self.assertTrue(any("launcher is not ELF" in x for x in report["errors"]))

if __name__ == "__main__":
    unittest.main()
