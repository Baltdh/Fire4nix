#!/usr/bin/env python3
"""Host test for safe periodic real-WPE Ninja progress, not a WebKit build."""
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path
import importlib.util
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/wpe-ninja-heartbeat.py"
spec = importlib.util.spec_from_file_location("wpe_ninja_heartbeat", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class WPEProgressTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.folder = Path(tmp.name)
        self.log = self.folder / "ninja.log"

    def execute(self, body, interval=1, timeout=4):
        output = StringIO()
        with redirect_stdout(output):
            exit_code = module.run(
                self.log, interval, timeout, [sys.executable, "-c", body]
            )
        return exit_code, output.getvalue()

    def test_success_with_numeric_progress_and_no_command_leak(self):
        # The subprocess output stays in the log, NOT the GitHub job summary.
        command = ("import sys,time; print('[1/4] SECRET_BUILD_COMMAND', flush=True);"
                   "time.sleep(1.35);print('[4/4] succeeded',flush=True)")
        code, status = self.execute(command)
        self.assertEqual(code, 0)
        self.assertIn("WPE_NINJA_PROGRESS=1/4", status)
        self.assertIn("exit_code=0", status)
        self.assertNotIn("SECRET_BUILD_COMMAND", status)
        self.assertIn("SECRET_BUILD_COMMAND", self.log.read_text())

    def test_nonzero_compiler_exit_propagated(self):
        code, status = self.execute(
            "import sys; print('FAILED: SECRET_LINKER_FLAGS',flush=True);sys.exit(17)"
        )
        self.assertEqual(code, 17)
        self.assertIn("exit_code=17", status)
        self.assertNotIn("SECRET_LINKER_FLAGS", status)
        self.assertIn("SECRET_LINKER_FLAGS", self.log.read_text())

    def test_timeout_preserves_gnu_124_status(self):
        code, status = self.execute("import time;time.sleep(3)", timeout=1)
        self.assertEqual(code, 124)
        self.assertIn("exit_code=124", status)

    def test_reject_unsafe_log_and_missing_command(self):
        target = self.folder / "target.txt"
        target.write_text("preserve")
        self.log.symlink_to(target)
        with self.assertRaisesRegex(ValueError, "NEED_SAFE"):
            module.run(self.log, 1, 2, [sys.executable])
        self.assertEqual(target.read_text(), "preserve")
        self.log.unlink()
        with self.assertRaisesRegex(ValueError, "NEED_SAFE"):
            module.run(self.log, 1, 2, [])
        with self.assertRaisesRegex(ValueError, "INVALID_INTERVAL"):
            module.run(self.log, 0, 2, [sys.executable])

    def test_bounded_tail_and_progress_counters(self):
        self.log.write_bytes(
            b"[1/70] first\\n" + b"no command output\\n" * 4500 +
            b"[45/70] last\\n")
        self.assertEqual(module.latest_counter(self.log), "45/70")
        self.log.write_bytes(b"COMPILER_CMD_WITHOUT_COUNTER\\n")
        self.assertEqual(module.latest_counter(self.log), "not_yet_available")


if __name__ == "__main__":
    unittest.main(verbosity=2)
