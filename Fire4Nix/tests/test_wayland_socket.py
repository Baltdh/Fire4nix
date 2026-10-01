"""Exercise launch selection with real Unix sockets; no compositor required."""
import os
import errno
from pathlib import Path
import socket
import subprocess
import tempfile
import unittest

HELPERS = Path(__file__).resolve().parents[1] / "scripts/fire4nix_env.sh"


class WaylandSocketTest(unittest.TestCase):
    def probe(self, display, runtime, command):
        env = os.environ.copy()
        for key in ("WAYLAND_DISPLAY", "XDG_RUNTIME_DIR", "WPE_PLATFORM",
                    "FIRE4NIX_WPE_PLATFORM", "FIRE4NIX_WPE_DISPLAY",
                    "FIRE4NIX_COG_PLATFORM"):
            env.pop(key, None)
        if display is not None:
            env["WAYLAND_DISPLAY"] = display
        if runtime is not None:
            env["XDG_RUNTIME_DIR"] = runtime
        return subprocess.run(["bash", "-c", '. "$1"; ' + command,
                               "socket-test", str(HELPERS)], env=env,
                              capture_output=True, text=True, check=False)

    def test_supported_socket_names_select_wayland(self):
        with tempfile.TemporaryDirectory() as root:
            try:
                server = socket.socket(socket.AF_UNIX)
            except OSError as error:
                if error.errno in (errno.EPERM, errno.EACCES):
                    self.skipTest("environment forbids Unix socket creation")
                raise
            with server:
                path = str(Path(root) / "wayland-0")
                server.bind(path)
                for display, runtime in (("wayland-0", root), (None, root),
                                         (path, None), (path, "/nonexistent")):
                    with self.subTest(display=display, runtime=runtime):
                        result = self.probe(display, runtime,
                            "fire4nix_wayland_socket_available && "
                            "fire4nix_wpe_platform_name && fire4nix_cog_platform_name")
                        self.assertEqual(result.returncode, 0, result.stderr)
                        self.assertEqual(result.stdout.splitlines(), ["wayland", "wl"])

    def test_socket_path_resolution(self):
        for display, runtime, expected in (
                ("wayland-1", "/tmp/session/", "/tmp/session/wayland-1"),
                (None, "/tmp/session", "/tmp/session/wayland-0"),
                ("/tmp/absolute-socket", None, "/tmp/absolute-socket"),
                ("/tmp/absolute-socket", "/wrong", "/tmp/absolute-socket")):
            with self.subTest(display=display, runtime=runtime):
                result = self.probe(display, runtime, "fire4nix_wayland_socket_path")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), expected)

    def test_missing_socket_and_regular_file_are_rejected(self):
        with tempfile.TemporaryDirectory() as root:
            path = str(Path(root) / "wayland-0")
            for create in (False, True):
                if create:
                    Path(path).touch()
                result = self.probe("wayland-0", root,
                                    "fire4nix_wayland_socket_available")
                self.assertNotEqual(result.returncode, 0)

    def test_relative_socket_requires_runtime_directory(self):
        result = self.probe("wayland-0", None, "fire4nix_wayland_socket_available")
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
