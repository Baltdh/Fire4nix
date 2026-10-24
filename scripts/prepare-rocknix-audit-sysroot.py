#!/usr/bin/env python3
"""Relocate a private copy of the pinned SDK for static analysis, never firmware.

Only absolute links rooted at the observed immutable SDK build prefix may be
rebased. The /lib alias models a merged-/usr analysis namespace; this does not
prove that the physical device has that layout or that its loader is compatible.
"""
from __future__ import annotations
import argparse
import os
from pathlib import Path
import shutil
import tempfile

ORIGINAL = Path('/home/runner/work/Fire4nix/Fire4nix/rocknix-source/'
                'build.ROCKNIX-RK3326.aarch64/toolchain/aarch64-rocknix-linux-gnu/sysroot')


def prepare(source: Path, output: Path) -> int:
    if not source.is_dir() or source.is_symlink():
        raise ValueError('INVALID_SYSROOT_SOURCE')
    if output.exists() or output.is_symlink() or not output.parent.is_dir():
        raise ValueError('INVALID_OR_EXISTING_SYSROOT_OUTPUT')
    source = source.resolve(strict=True)
    destination = output.resolve()
    if destination.is_relative_to(source) or source.is_relative_to(destination):
        raise ValueError('OVERLAPPING_SYSROOT_PATHS')
    links = {}
    for path in source.rglob('*'):
        if not path.is_symlink():
            if not (path.is_file() or path.is_dir()):
                raise ValueError('SPECIAL_SYSROOT_ENTRY')
            continue
        target = Path(os.readlink(path))
        if target.is_absolute():
            if not target.is_relative_to(ORIGINAL) or '..' in target.parts:
                raise ValueError('UNRECOGNIZED_ABSOLUTE_SDK_LINK:' + str(path.relative_to(source)))
            target = source / target.relative_to(ORIGINAL)
            # The pinned artifact uses direct links to regular files. Do not
            # resolve chains through an absolute link or outside this SDK.
            if target.is_symlink() or not target.is_file():
                raise ValueError('MISSING_PINNED_SDK_LINK_TARGET')
            links[path.relative_to(source)] = os.path.relpath(target, path.parent)
        else:
            try:
                resolved = path.resolve(strict=True)
            except (OSError, RuntimeError) as exc:
                raise ValueError('BROKEN_RELATIVE_SDK_LINK') from exc
            if not resolved.is_relative_to(source):
                raise ValueError('ESCAPING_RELATIVE_SDK_LINK')
    if not (source / 'usr/lib/ld-linux-aarch64.so.1').is_file():
        raise ValueError('MISSING_SDK_LOADER')
    if (source / 'lib').exists() or (source / 'lib').is_symlink():
        raise ValueError('UNEXPECTED_SDK_LIB_LAYOUT')
    with tempfile.TemporaryDirectory(prefix='.audit-sysroot-', dir=output.parent) as tmp:
        copy = Path(tmp) / 'sysroot'
        shutil.copytree(source, copy, symlinks=True)
        for relative, target in links.items():
            path = copy / relative
            path.unlink()
            path.symlink_to(target)
        (copy / 'lib').symlink_to('usr/lib', target_is_directory=True)
        for path in copy.rglob('*'):
            if path.is_symlink() and not path.resolve(strict=True).is_relative_to(copy.resolve()):
                raise ValueError('RELOCATED_SYSROOT_ESCAPE')
        os.rename(copy, output)
    return len(links)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    count = prepare(args.source, args.output)
    print(f'PINNED_SDK_LINKS_REBASED_IN_PRIVATE_COPY={count}')
    print('SYSROOT_LIB_ALIAS=STATIC_ANALYSIS_MERGED_USR_ONLY')
    print('DEVICE_LOADER_LAYOUT_VERIFIED=no')
    print('TARGET_EXECUTED=no')

if __name__ == '__main__':
    main()
