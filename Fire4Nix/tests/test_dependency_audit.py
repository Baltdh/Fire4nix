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

    def test_version_parser_distinguishes_definitions_from_requirements(self):
        needs, definitions = module.version_sections("""Version definition section '.gnu.version_d':
  Name: GLIBC_2.17
Version needs section '.gnu.version_r':
  File: libc.so.6 Cnt: 2
  Name: GLIBC_2.38 Flags: none Version: 2
  Name: OPTIONAL Flags: WEAK Version: 3
""")
        self.assertEqual(needs, {"libc.so.6": ["GLIBC_2.38"]})
        self.assertEqual(definitions, ["GLIBC_2.17"])

    def test_existing_library_with_older_abi_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ("browser", "libc.so.6"):
                (root / name).write_bytes(b"\x7fELF")
            def inspect(path):
                browser = path.name == "browser"
                return {"path": str(path), "machine": "AArch64", "needed": ["libc.so.6"] if browser else [], "soname": [], "symbol_versions": [], "interpreter": [],
                        "version_needs": {"libc.so.6": ["GLIBC_2.38"]} if browser else {},
                        "version_definitions": [] if browser else ["GLIBC_2.17"]}
            with patch.object(module, "inspect", side_effect=inspect):
                report = module.audit(root)
            self.assertEqual(report["missing"], [])
            self.assertEqual(report["incompatible_versions"][0]["missing_versions"], ["GLIBC_2.38"])

    def test_target_absolute_symlink_stays_inside_image(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "usr/lib").mkdir(parents=True)
            target = root / "usr/lib/libc-real.so"
            target.write_bytes(b"\x7fELF")
            link = root / "usr/lib/libc.so.6"
            link.symlink_to("/usr/lib/libc-real.so")
            self.assertEqual(module.resolve_target_path(link, root), target)

    def test_target_symlink_escape_and_loop_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            link = root / "escape"
            link.symlink_to("../outside")
            with self.assertRaises(ValueError):
                module.resolve_target_path(link, root)
            link.unlink()
            link.symlink_to("escape")
            with self.assertRaises(ValueError):
                module.resolve_target_path(link, root)

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
