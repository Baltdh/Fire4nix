#!/usr/bin/env python3
"""No-GPU regression: the real R36H EGL probe must not need a hardware device."""
from __future__ import annotations
import contextlib
import ctypes as C
import importlib.util
import io
from pathlib import Path
from unittest import TestCase, main, mock

FILE = Path(__file__).resolve().parents[2] / "diagnostics/Fire4Nix-EGL-R36H.py"
SPEC = importlib.util.spec_from_file_location("fire4nix_egl_probe", FILE)
probe = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(probe)


class Function:
    def __init__(self, callback):
        self.callback = callback
        self.restype = None
        self.argtypes = None

    def __call__(self, *args):
        return self.callback(*args)


class Library:
    def __init__(self, *, no_display=False, no_initialize=False, no_config=False):
        self.symbols = {}
        def assign(name, value):
            self.symbols[name] = Function(value)
        assign("eglGetDisplay", lambda *_: None if no_display else 11)
        def initialize(display, major, minor):
            C.cast(major, C.POINTER(C.c_int)).contents.value = 1
            C.cast(minor, C.POINTER(C.c_int)).contents.value = 5
            return 0 if no_initialize else 1
        assign("eglInitialize", initialize)
        assign("eglQueryString", lambda *_: b"EGL_EXT_platform_wayland EGL_KHR_platform_gbm")
        assign("eglGetError", lambda: 0x3000)
        assign("eglBindAPI", lambda *_: 1)
        def config(display, attrs, dest, max_configs, count):
            C.cast(dest, C.POINTER(C.c_void_p)).contents.value = 17
            C.cast(count, C.POINTER(C.c_int)).contents.value = 0 if no_config else 1
            return 1
        assign("eglChooseConfig", config)
        assign("eglCreateContext", lambda *_: 19)
        assign("eglCreatePbufferSurface", lambda *_: 23)
        assign("eglMakeCurrent", lambda *_: 1)
        assign("eglDestroyContext", lambda *_: 1)
        assign("eglDestroySurface", lambda *_: 1)
        assign("eglTerminate", lambda *_: 1)
        assign("glGetString", lambda attr: b"Mock Mali GLES2" if attr == probe.GL_RENDERER else b"OpenGL ES 2.0")

    def __getattr__(self, name):
        return self.symbols[name]


class EGLProbeTests(TestCase):
    def perform(self, **kwargs):
        egl = Library(**kwargs)
        out = io.StringIO()
        with mock.patch.object(probe.C, "CDLL", return_value=egl), \
             mock.patch.dict(probe.os.environ, {"MALI_DEFAULT_DISPLAY": "wayland"}, clear=True), \
             contextlib.redirect_stdout(out):
            code = probe.main()
        return code, out.getvalue()

    def test_full_context_creation_is_not_claimed_as_webkit_rendering(self):
        status, output = self.perform()
        self.assertEqual(status, 0)
        self.assertIn("egl_initialize=success", output)
        self.assertIn("egl_create_context=success", output)
        self.assertIn("egl_make_current=success", output)
        self.assertIn("gles_renderer=Mock Mali GLES2", output)
        self.assertIn("surfaceless_extension=no", output)
        self.assertIn("offscreen_context=PASS_NO_WEBKIT_OR_WAYLAND_FRAME_PROOF", output)

    def test_no_display_must_fail(self):
        code, output = self.perform(no_display=True)
        self.assertEqual(code, 3)
        self.assertIn("egl_get_display=failed:0x3000", output)
        self.assertNotIn("offscreen_context=PASS", output)

    def test_no_egl_initialize_must_fail(self):
        code, output = self.perform(no_initialize=True)
        self.assertEqual(code, 4)
        self.assertIn("egl_initialize=failed:", output)

    def test_no_gles2_pbuffer_config_must_fail(self):
        code, output = self.perform(no_config=True)
        self.assertEqual(code, 6)
        self.assertIn("egl_choose_config=failed_or_no_gles2_pbuffer_config", output)
        self.assertNotIn("offscreen_context=PASS", output)

if __name__ == "__main__":
    main(verbosity=2)
