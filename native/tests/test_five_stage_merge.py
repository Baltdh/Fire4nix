#!/usr/bin/env python3
"""Exercise the actual merge block without downloading or executing ARM code."""
from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
source = (repo / 'scripts/verify-five-rocknix-deps.sh').read_text()
merge = source.split("<<'PY'\n", 1)[1].split('\nPY\n', 1)[0]
with tempfile.TemporaryDirectory() as tmp:
    src, dst = Path(tmp) / 'src', Path(tmp) / 'dst'
    for root in (src, dst):
        for directory in ('usr/share/info', 'usr/include', 'usr/lib/pkgconfig'):
            (root / directory).mkdir(parents=True, exist_ok=True)
    (src / 'usr/share/info/dir').write_text('libffi catalog')
    (dst / 'usr/share/info/dir').write_text('existing catalog')
    for name in ('usr/include/ffi.h', 'usr/lib/libffi.a', 'usr/lib/pkgconfig/libffi.pc'):
        (src / name).write_text(name)

    def run():
        return subprocess.run(['python3', '-c', merge, str(src), str(dst)],
                              capture_output=True, text=True)

    result = run()
    assert result.returncode == 0, result.stderr
    assert (dst / 'usr/share/info/dir').read_text() == 'existing catalog'
    for name in ('usr/include/ffi.h', 'usr/lib/libffi.a', 'usr/lib/pkgconfig/libffi.pc'):
        assert (dst / name).read_bytes() == (src / name).read_bytes()
    assert run().returncode == 0, 'identical inputs must be idempotent'
    (src / 'usr/include/ffi.h').write_text('different header')
    result = run()
    assert result.returncode != 0 and 'content collision' in result.stderr
    (src / 'usr/include/ffi.h').write_text('usr/include/ffi.h')
    (src / 'usr/lib/escape').symlink_to('/tmp/outside-stage')
    result = run()
    assert result.returncode != 0 and 'unsafe link' in result.stderr
print('PASS: SDK files, generated catalog, idempotence, collision and unsafe link')
