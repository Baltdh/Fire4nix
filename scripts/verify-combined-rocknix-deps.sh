#!/usr/bin/env bash
# Combine three *genuine* ROCKNIX AArch64 target dependency artifacts into a
# private DESTDIR and link one ARM64 consumer against all three, without running it.
set -euo pipefail
case "${1:---check}" in --check) ;; --help)
  echo 'Usage: FIRE4NIX_COMBINED_WORK=$GITHUB_WORKSPACE/combined-rocknix bash scripts/verify-combined-rocknix-deps.sh --check'
  exit 0 ;;
  *) echo 'ERROR: --check only' >&2; exit 2 ;;
esac
[[ "${GITHUB_ACTIONS:-}" == true && "$(id -u)" != 0 && -n "${GITHUB_WORKSPACE:-}" ]] || {
  echo 'ERROR: CI non-root runner only; no device installations' >&2; exit 4;
}
base="$GITHUB_WORKSPACE"
work=${FIRE4NIX_COMBINED_WORK:-"$base/combined-rocknix"}
[[ "$work" == "$base/combined-rocknix" ]] || { echo 'ERROR: unexpected output path' >&2; exit 4; }
[[ ! -e "$work" && ! -L "$work" ]] || { echo 'ERROR: output exists' >&2; exit 4; }
for cmd in tar readelf sha256sum pkg-config python3; do
  command -v "$cmd" >/dev/null || { echo "ERROR: host tool missing $cmd" >&2; exit 4; }
done
sdk="$base/rocknix-source/build.ROCKNIX-RK3326.aarch64/toolchain"
sysroot="$sdk/aarch64-rocknix-linux-gnu/sysroot"
cc="$sdk/bin/aarch64-rocknix-linux-gnu-gcc"
[[ -x "$cc" && -s "$sysroot/usr/lib/libc.so.6" ]] || { echo 'ERROR: genuine ROCKNIX SDK not restored' >&2; exit 4; }
[[ "$("$cc" -dumpmachine)" == aarch64-rocknix-linux-gnu ]] || exit 4
[[ -s "$sdk/fire4nix-toolchain.cmake" ]] || exit 4
grep -Fq "$sdk" "$sdk/fire4nix-toolchain.cmake" || { echo 'ERROR: wrong checkpoint path' >&2; exit 4; }
readelf -h "$sysroot/usr/lib/libc.so.6" | grep -Eq 'Machine:.*AArch64'
mkdir -p "$work"/{stage,libtasn1-unpack,report,build}
stage="$work/stage"
# The artifact producer stores zlib and SQLite as directory trees.
for pkg in zlib sqlite; do
  case "$pkg" in
    zlib) upstream="$base/zlib-artifact/zlib-rocknix-target-only"; expected=zlib.pc ;;
    sqlite) upstream="$base/sqlite-artifact/sqlite-rocknix-target-only"; expected=sqlite3.pc ;;
  esac
  [[ -s "$upstream/usr/lib/pkgconfig/$expected" ]] || {
    echo "ERROR: missing actual $pkg development metadata from pinned Actions artifact" >&2; exit 5;
  }
done
archive="$base/libtasn1-artifact/libtasn1-4.21.0-ROCKNIX-RK3326-CROSS-STAGE-ONLY.tar.xz"
[[ -s "$archive" ]] || { echo 'ERROR: pinned libtasn1 stage missing' >&2; exit 5; }
# Preflight archive members before extraction. All paths must be relative and
# symlinks/hardlinks may not escape the private stage.
python3 - "$archive" "$work/libtasn1-unpack" <<'PY'
import pathlib, sys, tarfile
p, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
with tarfile.open(p, 'r:xz') as tar:
    for item in tar.getmembers():
        clean = pathlib.PurePosixPath(item.name)
        if clean.is_absolute() or '..' in clean.parts or not (item.isfile() or item.isdir() or item.issym()):
            raise SystemExit(f'ERROR: unsupported tar member {item.name}')
        if item.issym():
            link = pathlib.PurePosixPath(item.linkname)
            if link.is_absolute() or '..' in link.parts:
                raise SystemExit(f'ERROR: unsafe tar symlink {item.name}')
    tar.extractall(out, filter='data')
PY
[[ -s "$work/libtasn1-unpack/usr/lib/pkgconfig/libtasn1.pc" ]] || {
  echo 'ERROR: missing real libtasn1.pc'; exit 5;
}
# A collision with different contents is an error, never a silent overwrite.
python3 - "$stage" \
  "$base/zlib-artifact/zlib-rocknix-target-only" \
  "$base/sqlite-artifact/sqlite-rocknix-target-only" \
  "$work/libtasn1-unpack" <<'PY'
from pathlib import Path
import hashlib, shutil, sys
dest=Path(sys.argv[1])
dest.mkdir()
count=0
for source in (Path(p) for p in sys.argv[2:]):
    assert (source/'usr/lib').is_dir(), 'source without usr/lib'
    for f in sorted((source/'usr').rglob('*')):
        rel=f.relative_to(source)
        d=dest/rel
        if f.is_symlink():
            target=f.readlink()
            if target.is_absolute() or '..' in target.parts:
                raise SystemExit(f'ERROR: unsafe symlink: {f}')
            if d.is_symlink():
                if d.readlink()!=target: raise SystemExit(f'ERROR: symlink collision {d}')
            elif d.exists(): raise SystemExit(f'ERROR: type collision {d}')
            else:
                d.parent.mkdir(parents=True,exist_ok=True)
                d.symlink_to(target)
        elif f.is_dir():
            if d.is_symlink() or (d.exists() and not d.is_dir()):
                raise SystemExit(f'ERROR: dir collision {d}')
            d.mkdir(parents=True,exist_ok=True)
        elif f.is_file():
            if d.is_symlink() or (d.exists() and not d.is_file()):
                raise SystemExit(f'ERROR: file collision {d}')
            if d.exists():
                if hashlib.sha256(f.read_bytes()).digest()!=hashlib.sha256(d.read_bytes()).digest():
                    raise SystemExit(f'ERROR: differing content collision {d}')
            else:
                d.parent.mkdir(parents=True,exist_ok=True)
                shutil.copy2(f,d)
                count+=1
        else: raise SystemExit(f'ERROR: unsupported file {f}')
print(f'PRIVATE_STAGE_FILES_COPIED={count}')
PY
test -s "$stage/usr/include/zlib.h"
test -s "$stage/usr/include/sqlite3.h"
test -s "$stage/usr/include/libtasn1.h"
for pc in zlib sqlite3 libtasn1; do
  PKG_CONFIG_LIBDIR="$stage/usr/lib/pkgconfig" \
  PKG_CONFIG_SYSROOT_DIR="$stage" PKG_CONFIG_PATH='' \
    pkg-config --exists "$pc" || { echo "ERROR: target pc $pc unavailable"; exit 5; }
  PKG_CONFIG_LIBDIR="$stage/usr/lib/pkgconfig" \
  PKG_CONFIG_SYSROOT_DIR="$stage" PKG_CONFIG_PATH='' \
    pkg-config --modversion "$pc"
done > "$work/report/dependency-versions.txt"
# Reject binary mismatches, broken links, or accidental GStreamer.
while IFS= read -r -d '' file; do
  readelf -h "$file" | grep -Eq 'Class:.*ELF64' || exit 6
  readelf -h "$file" | grep -Eq 'Machine:.*AArch64' || exit 6
  if readelf -d "$file" | grep -Eq 'Shared library: \[libgst[^]]*\]'; then
    echo "ERROR: media library unexpectedly required in $file" >&2; exit 6
  fi
  required=$(readelf -V "$file" 2>/dev/null | grep -oE 'Name: GLIBC_[0-9]+\.[0-9]+' |
    sed 's/Name: GLIBC_//' | sort -Vu | tail -n1 || true)
  if [[ -n "$required" ]]; then
    awk -v req="$required" 'BEGIN {split(req,a,".");exit !(a[1]<2 || (a[1]==2 && a[2]<=41))}' || {
      echo "ERROR: newer GLIBC needed for $file: $required" >&2; exit 6;
    }
  fi
  printf '%s %s\n' "${required:-none}" "${file#"$stage"/}" >> "$work/report/elf-glibc.txt"
done < <(find "$stage/usr/lib" -type f -name '*.so*' -print0)
for needed in libz.so libsqlite3.so libtasn1.so; do
  [[ -e "$stage/usr/lib/$needed" ]] || { echo "ERROR: $needed missing"; exit 6; }
done
# AArch64 consumer links all three real libraries, rather than trusting .pc.
cat > "$work/build/combined-consumer.c" <<'C'
#include <zlib.h>
#include <sqlite3.h>
#include <libtasn1.h>
int main(void) {
    return (zlibVersion()[0] && sqlite3_libversion()[0] &&
            asn1_check_version(0)) ? 0 : 1;
}
C
"$cc" -O2 -mcpu=cortex-a35 \
  -I"$stage/usr/include" \
  -L"$stage/usr/lib" -Wl,-rpath-link,"$stage/usr/lib" \
  -o "$work/build/combined-consumer-aarch64" \
  "$work/build/combined-consumer.c" -Wl,--no-as-needed -lz -lsqlite3 -ltasn1
readelf -h "$work/build/combined-consumer-aarch64" > "$work/report/consumer-header.txt"
readelf -d "$work/build/combined-consumer-aarch64" > "$work/report/consumer-dynamic.txt"
readelf -V "$work/build/combined-consumer-aarch64" > "$work/report/consumer-versions.txt"
grep -Eq 'Machine:.*AArch64' "$work/report/consumer-header.txt"
for soname in libz.so.1 libsqlite3.so.0 libtasn1.so.6; do
  grep -Fq "Shared library: [$soname]" "$work/report/consumer-dynamic.txt" || {
    echo "ERROR: consumer did not link $soname" >&2; exit 6;
  }
done
{
  echo 'THREE_DEPENDENCY_STAGE=PASS_REAL_ROCKNIX_AARCH64'
  echo 'THREE_DEPENDENCY_CONSUMER_LINK=PASS_ALL_THREE_REAL_SONAMES'
  echo 'TARGET_MAX_GLIBC=2.41'
  echo 'LIBRARIES=zlib_1.3.1,sqlite_3.50.2,libtasn1_4.21.0'
  echo 'SYSTEM_SYSROOT_MODIFIED=no'
  echo 'WEBKIT_BUILT=no'
  echo 'R36H_EXECUTED=no'
  echo 'NOT_INSTALLABLE_ON_R36H=yes'
} | tee "$work/report/acceptance.txt"
(cd "$stage" && find usr -type f -print0 | sort -z | xargs -0 sha256sum) > "$work/report/stage-sha256sums.txt"
