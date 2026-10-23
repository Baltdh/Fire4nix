#!/usr/bin/env python3
"""Patch the SHA256-pinned, extracted WPE 2.54.1 tree for R36H runtime paths/EGL.

EGL_DEFAULT_DISPLAY initialization was observed on the device (EGL_SUCCESS).
Actual WebKit rendering still requires device validation. No firmware changes.
"""
import argparse
import hashlib
import json
from pathlib import Path

GUARD = '#if PLATFORM(GTK) || OS(ANDROID)'
WPE_GUARD = GUARD + ' || PLATFORM(WPE)'
GUARDED_FILES = (
    'Source/WebCore/platform/graphics/PlatformDisplay.h',
    'Source/WebCore/platform/graphics/egl/PlatformDisplayDefault.h',
    'Source/WebCore/platform/graphics/egl/PlatformDisplayDefault.cpp',
)
PROCESS = 'Source/WebKit/Shared/glib/ProcessExecutablePathGLib.cpp'
WEB = 'Source/WebKit/WebProcess/glib/WebProcessGLib.cpp'
MARKER = 'WPE2541_R36H_DEFAULT_EGL_AND_PRIVATE_EXEC_V1'
FALLBACK = '''#if PLATFORM(WPE)
    // Fire4Nix R36H: opt-in fallback after the normal GBM/surfaceless paths.
    // The Mali driver advertises Wayland but not EGL_MESA_platform_surfaceless.
    if (!g_strcmp0(g_getenv("FIRE4NIX_WPE_DEFAULT_EGL"), "1")) {
        WTFLogAlways("FIRE4NIX_WPE_EGL_FALLBACK=DEFAULT_DISPLAY");
        if (auto display = PlatformDisplayDefault::create()) {
            PlatformDisplay::setSharedDisplay(WTF::move(display));
            return;
        }
    }
#endif

'''


def once(text, old, new):
    if text.count(old) != 1:
        raise ValueError('SOURCE_ANCHOR_COUNT:' + old[:90])
    return text.replace(old, new, 1)


def transform(files):
    result = {}
    for path in GUARDED_FILES:
        result[path] = once(files[path], GUARD + '\n', WPE_GUARD + '\n')
    text = files[WEB]
    text = once(text, GUARD + '\n#include <WebCore/PlatformDisplayDefault.h>',
                WPE_GUARD + '\n#include <WebCore/PlatformDisplayDefault.h>')
    anchor = GUARD + '\n    if (auto display = PlatformDisplayDefault::create())'
    result[WEB] = once(text, anchor, FALLBACK + anchor)
    text = files[PROCESS]
    text = once(text, '#if ENABLE(DEVELOPER_MODE)\n    static const char* execDirectory',
                '    // Private Fire4Nix subprocess directory is also valid in release builds.\n    static const char* execDirectory')
    text = once(text, '    if (execDirectory) {', '    if (execDirectory && g_path_is_absolute(execDirectory)) {')
    text = once(text, '    static String executablePath = getExecutablePath();',
                '#if ENABLE(DEVELOPER_MODE)\n    static String executablePath = getExecutablePath();')
    result[PROCESS] = text
    return result


def apply(source_root, report):
    if source_root.is_symlink() or not source_root.is_dir():
        raise ValueError('UNSAFE_SOURCE_ROOT')
    root = source_root.resolve(strict=True)
    files = {}
    for name in (*GUARDED_FILES, WEB, PROCESS):
        file = root / name
        if file.is_symlink() or not file.is_file() or not file.resolve().is_relative_to(root):
            raise ValueError('UNSAFE_SOURCE_FILE:' + name)
        files[name] = file.read_text()
    # Validate all source anchors before changing any file.
    patched = transform(files)
    if report.is_symlink() or not report.parent.is_dir():
        raise ValueError('UNSAFE_REPORT')
    hashes = []
    for name, content in patched.items():
        (root / name).write_text(content)
        hashes.append(dict(file=name, before=hashlib.sha256(files[name].encode()).hexdigest(),
                           after=hashlib.sha256(content.encode()).hexdigest()))
    report.write_text(json.dumps(dict(patch=MARKER, files=hashes, device_rendering_verified=False), indent=2)+'\n')
    print('WPE_R36H_PLATFORM_PATCH=' + MARKER)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-root', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    apply(args.source_root, args.report)
