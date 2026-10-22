#!/usr/bin/env python3
"""Offline regression for stage-1 collision and symlink validation."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/assemble-step1-rocknix-stages.py"
spec = importlib.util.spec_from_file_location("step1", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def stage(root: Path, contents: bytes = b"same"):
    (root / "usr/lib").mkdir(parents=True)
    (root / "usr/include").mkdir(parents=True)
    (root / "usr/lib/libtest.so.1").write_bytes(contents)
    (root / "usr/include/test.h").write_bytes(b"header")


class StageTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.a, self.b, self.out = (
            self.root / "a", self.root / "b", self.root / "output"
        )
        stage(self.a)
        stage(self.b)

    def test_identical_source_files_are_allowed(self):
        self.assertGreater(module.copy_source(self.a, self.out), 0)
        self.assertEqual(module.copy_source(self.b, self.out), 0)
        self.assertEqual((self.out/"usr/lib/libtest.so.1").read_bytes(), b"same")

    def test_conflicting_shared_object_is_rejected(self):
        (self.b / "usr/lib/libtest.so.1").write_bytes(b"different")
        module.copy_source(self.a, self.out)
        with self.assertRaises(SystemExit):
            module.copy_source(self.b, self.out)

    def test_external_symlink_is_rejected(self):
        (self.b / "usr/lib/libescape.so").symlink_to("/usr/lib/libc.so.6")
        with self.assertRaises(SystemExit):
            module.copy_source(self.b, self.out)

    def test_parent_traversal_symlink_is_rejected(self):
        (self.b / "usr/lib/libescape.so").symlink_to("../../host.so")
        with self.assertRaises(SystemExit):
            module.copy_source(self.b, self.out)

    def test_header_collision_is_rejected(self):
        (self.b / "usr/include/test.h").write_bytes(b"changed")
        module.copy_source(self.a, self.out)
        with self.assertRaises(SystemExit):
            module.copy_source(self.b, self.out)


if __name__ == "__main__":
    unittest.main()
