#!/usr/bin/env python3
"""Read-only EGL/GLES context probe for the ROCKNIX R36H/Mali Wayland driver.

Usage on the R36H, from a ROCKNIX Sway terminal (no root required):
    MALI_DEFAULT_DISPLAY=wayland timeout 15s python3 Fire4Nix-EGL-R36H.py

Only the selected process creates an EGL display and a 1x1 offscreen pbuffer;
no filesystem, firmware, network, user input or system services are modified.
A successful context is NOT proof that WPE draws into a Wayland surface.
"""
from __future__ import annotations

import ctypes as C
import os
import sys

EGL_DEFAULT_DISPLAY = C.c_void_p()
EGL_NONE = 0x3038
EGL_EXTENSIONS = 0x3055
EGL_VENDOR = 0x3053
EGL_VERSION_STRING = 0x3054
EGL_CLIENT_APIS = 0x308D
EGL_SURFACE_TYPE = 0x3033
EGL_PBUFFER_BIT = 0x0001
EGL_RENDERABLE_TYPE = 0x3040
EGL_OPENGL_ES2_BIT = 0x0004
EGL_OPENGL_ES_API = 0x30A0
EGL_CONTEXT_CLIENT_VERSION = 0x3098
EGL_WIDTH = 0x3057
EGL_HEIGHT = 0x3056
GL_RENDERER = 0x1F01
GL_VERSION = 0x1F02


def bind(library, symbol, restype, argtypes):
    proc = getattr(library, symbol)
    proc.restype = restype
    proc.argtypes = argtypes
    return proc


def reason(library):
    return "0x%04x" % (library.eglGetError() & 0xFFFF)


def report(name, value):
    print("%s=%s" % (name, value), flush=True)


def main():
    report("probe", "fire4nix-r36h-egl-gles2-readonly-v1")
    report("mali_default_display", os.getenv("MALI_DEFAULT_DISPLAY", "unset"))
    wayland_display = os.getenv("WAYLAND_DISPLAY", "wayland-0")
    runtime_dir = os.getenv("XDG_RUNTIME_DIR")
    report("wayland_display", wayland_display)
    report("xdg_runtime_dir", "present" if runtime_dir else "unset")
    socket_path = ""
    if os.path.isabs(wayland_display):
        socket_path = wayland_display
    elif runtime_dir:
        socket_path = os.path.join(runtime_dir, wayland_display)
    report("wayland_socket", "present" if socket_path and os.path.exists(socket_path) else "not_found")
    if os.getenv("MALI_DEFAULT_DISPLAY") != "wayland":
        report("warning", "set_MALI_DEFAULT_DISPLAY=wayland_for_device_comparison")
    try:
        egl = C.CDLL("libEGL.so.1")
    except OSError as exc:
        report("egl_library", "unavailable:%s" % exc.__class__.__name__)
        return 2
    display_fn = bind(egl, "eglGetDisplay", C.c_void_p, [C.c_void_p])
    init = bind(egl, "eglInitialize", C.c_uint, [C.c_void_p, C.POINTER(C.c_int), C.POINTER(C.c_int)])
    query = bind(egl, "eglQueryString", C.c_char_p, [C.c_void_p, C.c_int])
    choose = bind(egl, "eglChooseConfig", C.c_uint,
                  [C.c_void_p, C.POINTER(C.c_int), C.POINTER(C.c_void_p), C.c_int, C.POINTER(C.c_int)])
    api = bind(egl, "eglBindAPI", C.c_uint, [C.c_uint])
    create_context = bind(egl, "eglCreateContext", C.c_void_p,
                          [C.c_void_p, C.c_void_p, C.c_void_p, C.POINTER(C.c_int)])
    create_pbuffer = bind(egl, "eglCreatePbufferSurface", C.c_void_p,
                          [C.c_void_p, C.c_void_p, C.POINTER(C.c_int)])
    make_current = bind(egl, "eglMakeCurrent", C.c_uint,
                        [C.c_void_p, C.c_void_p, C.c_void_p, C.c_void_p])
    destroy_context = bind(egl, "eglDestroyContext", C.c_uint, [C.c_void_p, C.c_void_p])
    destroy_surface = bind(egl, "eglDestroySurface", C.c_uint, [C.c_void_p, C.c_void_p])
    terminate = bind(egl, "eglTerminate", C.c_uint, [C.c_void_p])
    bind(egl, "eglGetError", C.c_uint, [])
    exts = query(None, EGL_EXTENSIONS)
    if exts:
        advertised = exts.decode("ascii", "replace").split()
        for name, key in (
            ("EGL_EXT_platform_wayland", "wayland_extension"),
            ("EGL_KHR_platform_gbm", "gbm_extension"),
            ("EGL_MESA_platform_surfaceless", "surfaceless_extension"),
        ):
            report(key, "yes" if name in advertised else "no")
    display = display_fn(EGL_DEFAULT_DISPLAY)
    if not display:
        report("egl_get_display", "failed:%s" % reason(egl))
        return 3
    major, minor = C.c_int(), C.c_int()
    if not init(display, C.byref(major), C.byref(minor)):
        report("egl_initialize", "failed:%s" % reason(egl))
        return 4
    report("egl_initialize", "success")
    report("egl_version", "%d.%d" % (major.value, minor.value))
    for label, token in (
        ("egl_vendor", EGL_VENDOR),
        ("egl_display_version", EGL_VERSION_STRING),
        ("egl_client_apis", EGL_CLIENT_APIS),
    ):
        value = query(display, token)
        report(label, value.decode("utf-8", "replace") if value else "unavailable")
    surface, context = None, None
    try:
        if not api(EGL_OPENGL_ES_API):
            report("egl_bind_es", "failed:%s" % reason(egl))
            return 5
        attributes = (C.c_int * 5)(
            EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
            EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT, EGL_NONE)
        config = C.c_void_p()
        count = C.c_int()
        if not choose(display, attributes, C.byref(config), 1, C.byref(count)) or count.value < 1:
            report("egl_choose_config", "failed_or_no_gles2_pbuffer_config:%s" % reason(egl))
            return 6
        report("egl_choose_config", "success")
        context_attrs = (C.c_int * 3)(EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE)
        context = create_context(display, config, None, context_attrs)
        if not context:
            report("egl_create_context", "failed:%s" % reason(egl))
            return 7
        report("egl_create_context", "success")
        pbuffer_attrs = (C.c_int * 5)(EGL_WIDTH, 1, EGL_HEIGHT, 1, EGL_NONE)
        surface = create_pbuffer(display, config, pbuffer_attrs)
        if not surface:
            report("egl_create_pbuffer", "failed:%s" % reason(egl))
            return 8
        report("egl_create_pbuffer", "success")
        if not make_current(display, surface, surface, context):
            report("egl_make_current", "failed:%s" % reason(egl))
            return 9
        report("egl_make_current", "success")
        try:
            gles = C.CDLL("libGLESv2.so.2")
            get_string = bind(gles, "glGetString", C.c_char_p, [C.c_uint])
            renderer = get_string(GL_RENDERER)
            version = get_string(GL_VERSION)
            report("gles_renderer", renderer.decode("utf-8", "replace") if renderer else "unknown")
            report("gles_version", version.decode("utf-8", "replace") if version else "unknown")
        except OSError:
            report("gles_library", "unavailable")
            return 10
        report("offscreen_context", "PASS_NO_WEBKIT_OR_WAYLAND_FRAME_PROOF")
        return 0
    finally:
        # EGL is process-local. Never touch global or system GPU configuration.
        if surface or context:
            make_current(display, None, None, None)
        if surface:
            destroy_surface(display, surface)
        if context:
            destroy_context(display, context)
        terminate(display)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (AttributeError, ValueError) as exc:
        report("probe_error", type(exc).__name__)
        sys.exit(11)
