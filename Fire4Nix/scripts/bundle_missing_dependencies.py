#!/usr/bin/env python3
"""Stage missing ARM64 dependencies; never replace target system libraries."""
import argparse
import json
from pathlib import Path
import shutil
from audit_runtime_dependencies import audit, inspect, resolve_target_path

PROTECTED = ('libc.so', 'libm.so', 'libpthread.so', 'libdl.so', 'librt.so',
             'ld-linux', 'libEGL.so', 'libGLES', 'libGL.so', 'libgbm.so', 'libdrm.so')

def bundle(runtime, target, source, launcher=None):
    copied = []
    library_dir = runtime / 'lib'
    library_dir.mkdir(parents=True, exist_ok=True)
    for iteration in range(30):
        report = audit(runtime, target, (launcher,) if launcher else ())
        missing = sorted({item['library'] for item in report['missing']})
        if not missing:
            return {'copied': copied, 'audit': report}
        progress = False
        for name in missing:
            if name.startswith(PROTECTED):
                continue
            candidates = []
            for folder in ('usr/lib/aarch64-linux-gnu', 'lib/aarch64-linux-gnu', 'usr/lib', 'lib'):
                candidates.extend(sorted((source / folder).glob(name)))
            for candidate in candidates:
                resolved = resolve_target_path(candidate, source)
                if not resolved.is_file():
                    continue
                metadata = inspect(resolved)
                if metadata['machine'] != 'AArch64' or name not in metadata['soname']:
                    continue
                destination = library_dir / name
                if destination.exists():
                    continue
                shutil.copyfile(resolved, destination)
                destination.chmod(0o644)
                copied.append({'library': name, 'source': str(resolved)})
                progress = True
                break
        if not progress:
            return {'copied': copied, 'audit': report}
    raise RuntimeError('dependency staging did not converge')

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('runtime', type=Path)
    parser.add_argument('--target', type=Path, required=True)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--launcher', type=Path)
    args = parser.parse_args()
    for directory in (args.runtime, args.target, args.source):
        if not directory.is_dir():
            parser.error('missing directory: ' + str(directory))
    result = bundle(args.runtime.resolve(), args.target.resolve(), args.source.resolve(), args.launcher)
    print(json.dumps(result, indent=2))
    report = result['audit']
    return int(bool(report['errors'] or report['missing'] or report.get('incompatible_versions')))

if __name__ == '__main__':
    raise SystemExit(main())
