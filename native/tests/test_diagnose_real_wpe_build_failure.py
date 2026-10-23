#!/usr/bin/env python3
"""Fail-closed host fixture tests for the genuine WPE build-log postprocessor."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/diagnose-real-wpe-build-failure.py"
spec = importlib.util.spec_from_file_location("diagnose_real_wpe", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class RealWPEBuildDiagnosticTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.logs = self.root / "wpe-unified-sdk-build" / "report"
        self.logs.mkdir(parents=True)

    def write(self, filename, content):
        (self.logs / filename).write_text(content)

    def test_compiler_failure_identifies_fourcc(self):
        self.write("wpe-subprocesses-result.txt", "WPE_SUBPROCESS_CMAKE_EXIT=10\n")
        self.write("wpe-subprocesses-build.log",
                   "[8763/8822] Building CXX object\n"
                   "FAILED: Source/WebKit/AcceleratedBackingStore.o\n"
                   "/home/runner/work/private/AcceleratedBackingStore.cpp:220:57: "
                   "error: 'DRM_FORMAT_XRGB8888' was not declared in this scope\n"
                   "ninja: build stopped: subcommand failed.\n")
        result = module.analyze(self.root)
        self.assertIn("WPE_FAILURE_CLASS=WPE_2541_DRM_FOURCC_SOURCE", result)
        self.assertIn("WPE_BUILD_REPORTED_EXIT=10", result)
        self.assertIn("AcceleratedBackingStore.cpp", result)
        self.assertNotIn("/home/runner", result)
        self.assertIn("R36H_INSTALLABLE=no", result)

    def test_link_error_is_distinguished(self):
        self.write("wpe-subprocesses-build.log",
                   "FAILED: libWPEWebKit-2.0.so.1\n"
                   "/usr/bin/aarch64-gcc: undefined reference to WPEPlatformSymbol\n")
        self.assertIn("WPE_FAILURE_CLASS=ELF_LINK_FAILURE",
                      module.analyze(self.root))

    def test_runner_out_of_memory(self):
        self.write("wpe-subprocesses-build.log",
                   "c++: fatal error: Killed signal terminated program cc1plus\n")
        self.assertIn("WPE_FAILURE_CLASS=RUNNER_RESOURCE_FAILURE",
                      module.analyze(self.root))

    def test_no_logs_is_not_failure_claim(self):
        result = module.analyze(self.root)
        self.assertIn("WPE_FAILURE_CLASS=UNDETERMINED", result)
        self.assertIn("WPE_FIRST_ERROR_PRESENT=no", result)

    def test_reject_duplicate_report_locations(self):
        other = self.root / "another" / "report"
        other.mkdir(parents=True)
        self.write("wpe-subprocesses-build.log", "anything\n")
        (other / "wpe-subprocesses-build.log").write_text("anything else\n")
        with self.assertRaisesRegex(ValueError, "AMBIGUOUS_BUILD_REPORT"):
            module.analyze(self.root)

    def test_skip_escaping_symlink(self):
        outside = self.root / "outside.txt"
        outside.write_text("error: secret should not be read\n")
        (self.logs / "wpe-subprocesses-build.log").symlink_to(outside)
        result = module.analyze(self.root)
        self.assertIn("WPE_FAILURE_CLASS=UNDETERMINED", result)
        self.assertNotIn("secret", result)


if __name__ == "__main__":
    unittest.main(verbosity=2)
