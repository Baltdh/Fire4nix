#!/usr/bin/env python3
"""Offline, read-only WPE/ROCKNIX AArch64 ELF dependency audit.

Checks staged WPE libraries and processes against libraries in the *target*
ROCKNIX sysroot. Never executes ELF, looks at host ldconfig or opens network.
This is an early packaging gate, not proof that graphics, TLS or browsing works.
"""
import argparse
import os
from pathlib import Path
import re
import subprocess
import sys

NEEDED = re.compile(r'\(NEEDED\).*?Shared library: \[([^\]]+)\]')
RUNPATH = re.compile(r'\((?:RPATH|RUNPATH)\).*?Library (?:rpath|runpath): \[([^\]]+)\]')
GLIBC = re.compile(r'Name: GLIBC_(\d+)\.(\d+)(?:\.(\d+))?\b')
TARGET_DIRS = ('lib', 'lib64', 'lib/aarch64-linux-gnu',
               'usr/lib', 'usr/lib64', 'usr/lib/aarch64-linux-gnu')
CHILDREN = ('WPEWebProcess', 'WPENetworkProcess', 'WPEGPUProcess')


def within(path: Path, root: Path) -> bool:
    return path == root or root in path.parents


def source_file(path: Path, root: Path, sdk: bool):
    """Resolve links inside a bundle, rebasing SDK absolute links to SDK root."""
    current = path
    for _ in range(20):
        if not within(current, root):
            return None, 'LINK_ESCAPES_ROOT'
        # A lexical prefix is insufficient: a parent directory such as
        # sysroot/usr/lib may itself be a symlink to the build host's /usr/lib.
        if not within(current.parent.resolve(), root):
            return None, 'PARENT_ESCAPES_ROOT'
        if not current.is_symlink():
            return (current, None) if current.is_file() else (None, 'MISSING_TARGET')
        link = Path(os.readlink(current))
        if link.is_absolute():
            if not sdk:
                return None, 'ABSOLUTE_RUNTIME_SYMLINK'
            current = root / str(link).lstrip('/')
        else:
            current = current.parent / link
        current = Path(os.path.normpath(current))
    return None, 'SYMLINK_LOOP'


def readelf(path: Path, flag: str):
    try:
        proc = subprocess.run(['readelf', flag, str(path)], capture_output=True,
                              text=True, errors='replace', timeout=25, check=False)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return None, str(exc)
    return (proc.stdout, None) if proc.returncode == 0 else (None, proc.stderr.strip())


def too_new(version: tuple[int, ...], maximum: tuple[int, ...]) -> bool:
    return version > maximum


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime', type=Path, required=True, help='Isolated WPE runtime root')
    parser.add_argument('--sysroot', type=Path, required=True, help='ROCKNIX AArch64 target sysroot')
    parser.add_argument('--glibc-max', default='2.41', choices=['2.41', '2.44'])
    parser.add_argument('--inspect', action='store_true', help='Report failures without exit 6')
    parser.add_argument('--strict', action='store_true', help='Block packaging on any finding')
    args = parser.parse_args()
    if args.strict == args.inspect:
        parser.error('choose exactly one of --inspect or --strict')
    for name, p in [('runtime', args.runtime), ('sysroot', args.sysroot)]:
        if not p.is_absolute() or not p.is_dir():
            parser.error(f'{name} must be an existing absolute directory')
        resolved = p.resolve()
        if resolved in (Path('/'), Path('/usr'), Path('/lib'), Path('/lib64')):
            parser.error(f'{name} must be isolated, never the host system root')
    runtime = args.runtime.resolve()
    sdk = args.sysroot.resolve()
    if within(runtime, sdk) or within(sdk, runtime):
        parser.error('runtime and target sysroot must be separate trees')
    maximum = tuple(int(x) for x in args.glibc_max.split('.'))
    failures = set()
    visited = set()
    queue = []
    machine_checked = 0
    needed_checked = 0

    def fail(code, detail):
        failures.add((code, detail))

    def include(path, origin):
        nonlocal machine_checked, needed_checked
        if path in visited:
            return
        visited.add(path)
        header, err = readelf(path, '-h')
        if err or not re.search(r'Class:\s*ELF64\b', header) or not re.search(r'Machine:\s*AArch64\b', header):
            fail('BAD_ELF_OR_ARCH', f'{origin}:{path.name}')
            return
        machine_checked += 1
        versions, err = readelf(path, '-V')
        if err:
            fail('BAD_VERSION_TABLE', f'{origin}:{path.name}')
            return
        required = {(int(m.group(1)), int(m.group(2))) for m in GLIBC.finditer(versions)}
        if required and too_new(max(required), maximum):
            fail('GLIBC_TOO_NEW', f'{origin}:{path.name}:GLIBC_{max(required)[0]}.{max(required)[1]}')
        symbols, err = readelf(path, '--dyn-syms')
        if err:
            fail('BAD_DYNAMIC_SYMBOLS', f'{origin}:{path.name}')
        elif re.search(r'\bUND\s+GST_CAT_DEFAULT(?:\s|$)', symbols, re.M):
            fail('UNDEFINED_GST_CAT_DEFAULT', f'{origin}:{path.name}')
        dynamic, err = readelf(path, '-d')
        if err:
            fail('BAD_DYNAMIC_SECTION', f'{origin}:{path.name}')
            return
        for m in RUNPATH.finditer(dynamic):
            for component in m.group(1).split(':'):
                normalized = component.replace('$' + '{ORIGIN}', '$ORIGIN')
                # Subprocesses legitimately use $ORIGIN/../../lib to reach the
                # runtime's private lib directory. Permit that only when the
                # lexical result stays inside this isolated runtime/sysroot.
                if normalized == '$ORIGIN':
                    offset = ''
                elif normalized.startswith('$ORIGIN/'):
                    offset = normalized[len('$ORIGIN/'):]
                else:
                    fail('UNSAFE_RUNPATH', f'{origin}:{path.name}:{component}')
                    continue
                allowed_root = runtime if within(path, runtime) else sdk
                destination = Path(os.path.normpath(path.parent / offset))
                if not within(destination, allowed_root):
                    fail('UNSAFE_RUNPATH', f'{origin}:{path.name}:{component}')
        for soname in NEEDED.findall(dynamic):
            needed_checked += 1
            if soname.startswith('libgst') or soname.startswith('libgstreamer'):
                fail('GSTREAMER_LINKED', f'{origin}:{path.name}:{soname}')
            if not re.fullmatch(r'[A-Za-z0-9_.+\-]+', soname):
                fail('UNSAFE_NEEDED_NAME', f'{origin}:{path.name}:{soname}')
                continue
            queue.append((soname, path.name))

    roots = [runtime / 'lib/libWPEWebKit-2.0.so.1']
    roots.extend(runtime / 'libexec/wpe-webkit-2.0' / child for child in CHILDREN)
    # An unreferenced .so can still be loaded by dlopen; inspect every bundled ELF.
    libdir = runtime / 'lib'
    if libdir.is_dir():
        roots.extend(p for p in libdir.iterdir() if '.so' in p.name)
    for root_file in roots:
        if not root_file.exists() and not root_file.is_symlink():
            fail('REQUIRED_FILE_MISSING', root_file.name)
            continue
        actual, err = source_file(root_file, runtime, sdk=False)
        if err:
            fail('BAD_RUNTIME_SYMLINK', f'{root_file.name}:{err}')
        elif actual is not None:
            include(actual, 'runtime')
    while queue:
        soname, requester = queue.pop(0)
        providers = [runtime / 'lib' / soname]
        providers.extend(sdk / d / soname for d in TARGET_DIRS)
        provider = None
        where = None
        for candidate in providers:
            if candidate.is_symlink() or candidate.exists():
                root = runtime if within(candidate, runtime) else sdk
                actual, err = source_file(candidate, root, sdk=(root == sdk))
                if err:
                    fail('BAD_PROVIDER_LINK', f'{soname}:{err}')
                    break
                provider = actual
                where = 'runtime' if root == runtime else 'target_sysroot'
                break
        if provider is None:
            if not any(code == 'BAD_PROVIDER_LINK' and detail.startswith(soname + ':') for code, detail in failures):
                fail('MISSING_NEEDED_IN_TARGET', f'{requester}:{soname}')
        else:
            include(provider, where)
    print('AUDIT_PROFILE=ROCKNIX_AARCH64_MEDIA_FREE')
    print('ELF_FILES_CHECKED=' + str(machine_checked))
    print('DT_NEEDED_ENTRIES=' + str(needed_checked))
    print('TARGET_GLIBC_MAX=' + args.glibc_max)
    for code, detail in sorted(failures):
        print(f'FAIL_{code}={detail}')
    print('FINDING_COUNT=' + str(len(failures)))
    if failures:
        print('CLOSURE_STATUS=BLOCKED')
        return 6 if args.strict else 0
    print('CLOSURE_STATUS=PASS_STATIC_TARGET_ELF_AUDIT_ONLY')
    print('VALIDATION_LIMIT=NO_RUNTIME_EXECUTION_OR_WAYLAND_TEST')
    return 0


if __name__ == '__main__':
    sys.exit(main())
