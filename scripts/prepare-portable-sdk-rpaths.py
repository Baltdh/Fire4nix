#!/usr/bin/env python3
"""Remove redundant system-only RPATHs in a private SDK copy before bundling."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess

spec = importlib.util.spec_from_file_location('rpath_audit', Path(__file__).with_name('sanitize-rocknix-build-rpath.py'))
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)
SYSTEM = frozenset(('/lib', '/lib64', '/usr/lib', '/usr/lib64'))


def removable(paths):
    if not paths:
        return False
    parts = [part for _, value in paths for part in value.split(':')]
    if all(part in SYSTEM for part in parts):
        return True
    if all(part == '$ORIGIN' or (part.startswith('$ORIGIN/') and
           '..' not in Path(part).parts) for part in parts):
        return False
    raise ValueError('UNEXPECTED_SDK_RPATH:' + repr(paths))


def prepare(source, output):
    source = source.resolve(strict=True)
    if output.exists() or output.is_symlink():
        raise ValueError('EXISTING_PORTABLE_SDK_OUTPUT')
    if output.resolve().is_relative_to(source) or source.is_relative_to(output.resolve()):
        raise ValueError('OVERLAPPING_SDK_OUTPUT')
    candidates = []
    for file in sorted(source.rglob('*')):
        if file.is_symlink():
            if not file.resolve(strict=True).is_relative_to(source):
                raise ValueError('ESCAPING_SDK_LINK')
            continue
        if file.is_file() and (file.name.endswith('.so') or '.so.' in file.name):
            with file.open('rb') as stream:
                if stream.read(4) != b'\x7fELF':
                    continue  # linker scripts are not dynamic libraries
            before = audit.details(file)
            if removable(before['runpaths']):
                candidates.append((file, before))
    shutil.copytree(source, output, symlinks=True)
    report = []
    for original, before in candidates:
        dest = output / original.relative_to(source)
        audit.run('patchelf', '--remove-rpath', str(dest))
        after = audit.details(dest)
        if after['runpaths'] or any(before[k] != after[k] for k in ('dynamic', 'glibc')):
            raise ValueError('SDK_ABI_METADATA_CHANGED:' + str(dest))
        report.append({'file': str(original.relative_to(source)),
                       'removed': before['runpaths'],
                       'input_sha256': hashlib.sha256(original.read_bytes()).hexdigest(),
                       'output_sha256': hashlib.sha256(dest.read_bytes()).hexdigest()})
    (output / 'PORTABLE-RPATH-REPORT.json').write_text(json.dumps(report, indent=2) + '\n')
    print('SYSTEM_RPATH_REMOVED_PRIVATE_COPIES=' + str(len(report)))
    print('TARGET_EXECUTED=no')


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    prepare(args.source, args.output)
