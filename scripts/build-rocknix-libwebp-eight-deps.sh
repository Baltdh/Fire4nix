#!/usr/bin/env bash
# Genuine ROCKNIX RK3326 AArch64 libwebp 1.6.0 build using the verified
# seven-dependency target stage. Build-host CI only; do not run target ELFs.
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && "$(id -u)" != 0 && -n "${GITHUB_WORKSPACE:-}" ]] || {
  echo 'ERROR: requires non-root GitHub Actions runner' >&2; exit 4;
}
root="$GITHUB_WORKSPACE"
[[ "$(pwd -P)" == "$root" ]] || { echo 'ERROR: execute from GitHub workspace' >&2; exit 4; }
sdk="$root/rocknix-source/build.ROCKNIX-RK3326.aarch64/toolchain"
cc="$sdk/bin/aarch64-rocknix-linux-gnu-gcc"
sysroot="$sdk/aarch64-rocknix-linux-gnu/sysroot"
report="$root/webp-reports"
stage="$root/eight-rocknix-stage"
archive="$RUNNER_TEMP/libwebp-1.6.0.tar.gz"
source_dir="$RUNNER_TEMP/libwebp-1.6.0"
build_dir="$RUNNER_TEMP/webp-aarch64-build"
seven="$root/seven-artifact/seven-deps"
if [[ ! -s "$seven/report/result.txt" && -s "$root/seven-artifact/report/result.txt" ]]; then
  seven="$root/seven-artifact"
fi
[[ -s "$seven/report/result.txt" && -d "$seven/stage/usr/lib" ]] || {
  echo 'ERROR: pinned seven real dependency stage absent' >&2; exit 5;
}
grep -Fxq 'SEVEN_DEPENDENCY_STAGE=PASS_REAL_ROCKNIX_AARCH64' "$seven/report/result.txt"
grep -Fxq 'SEVEN_CONSUMER_LINK=PASS_GLIB_GOBJECT_GIO_GMODULE' "$seven/report/result.txt"
[[ "$(git -C "$root/rocknix-source" rev-parse HEAD)" == 3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb ]] || exit 5
[[ "$("$cc" -dumpmachine)" == aarch64-rocknix-linux-gnu ]] || exit 5
[[ -s "$sdk/fire4nix-toolchain.cmake" && -s "$sysroot/usr/lib/libc.so.6" ]] || exit 5
grep -Fq "$sdk" "$sdk/fire4nix-toolchain.cmake"
readelf -h "$sysroot/usr/lib/libc.so.6" | grep -Eq 'Machine:.*AArch64'
[[ ! -e "$stage" && ! -L "$stage" ]] || { echo 'ERROR: output stage already exists' >&2; exit 5; }
mkdir -p "$stage" "$report"
# The GitHub artifact service dereferences/loses symlinks, so recover only
# relative links from real SONAMEs of AArch64 ELF shared libraries.
python3 - "$seven/stage" "$stage" <<'PY'
from pathlib import Path
import hashlib, re, shutil, subprocess, sys
src, dst=map(Path,sys.argv[1:])
assert (src/'usr/lib').is_dir(), 'invalid real seven-library artifact'
for entry in sorted((src/'usr').rglob('*')):
    rel=entry.relative_to(src)
    out=dst/rel
    if entry.is_symlink():
        target=entry.readlink()
        if target.is_absolute() or '..' in target.parts: raise SystemExit(f'unsafe link {rel}')
        out.parent.mkdir(parents=True, exist_ok=True)
        out.symlink_to(target)
    elif entry.is_dir():
        out.mkdir(parents=True, exist_ok=True)
    elif entry.is_file():
        out.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(entry,out)
    else: raise SystemExit(f'unsupported source entry {rel}')
directory=dst/'usr/lib'
for f in sorted(directory.glob('lib*.so*')):
    if not f.is_file() or f.is_symlink(): continue
    head=subprocess.run(['readelf','-h',str(f)],capture_output=True,text=True)
    if head.returncode or not re.search(r'Machine:\s+AArch64',head.stdout): continue
    dyn=subprocess.run(['readelf','-d',str(f)],capture_output=True,text=True)
    so=re.findall(r'\(SONAME\).*\[([^\]]+)\]',dyn.stdout)
    if len(so)!=1: continue
    name=so[0]
    if not name.startswith('lib') or '/' in name or '..' in name: raise SystemExit(f'unsafe SONAME {f}')
    # GitHub upload-artifact can store development .so links as regular files.
    # Only a SONAME-bearing filename is authoritative for reconstruction.
    if not f.name.startswith(name): continue
    for link in (name,name.split('.so',1)[0]+'.so'):
        target=directory/link
        if target==f: continue
        if target.is_symlink() and target.readlink()==Path(f.name): continue
        if target.is_file() and not target.is_symlink() and hashlib.sha256(target.read_bytes()).digest()==hashlib.sha256(f.read_bytes()).digest(): continue
        if target.exists() or target.is_symlink(): raise SystemExit(f'inconsistent SONAME link {target}')
        target.symlink_to(f.name)
assert (directory/'libglib-2.0.so').exists()
assert (directory/'libpng16.so').exists()
assert (directory/'libz.so').exists()
print('SEVEN_STAGE_RESTORED=PASS_REAL_AARCH64')
PY
grep -Fxq 'PKG_VERSION="1.6.0"' \
  "$root/rocknix-source/projects/ROCKNIX/packages/graphics/libwebp/package.mk"
# The project override pins 1.6.0 but has no SHA256. Here use a verified
# 1.6.0 official release tarball with Buildroot source-hash provenance,
# not the auto-generated GitHub tag tarball.
expected=e4ab7009bf0629fd11982d4c2aa83964cf244cffba7347ecd39019a9e38c4564
curl -fLsS --proto '=https' --proto-redir '=https' \
  --connect-timeout 15 --max-time 100 \
  'https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-1.6.0.tar.gz' \
  -o "$archive"
echo "$expected  $archive" | sha256sum -c -
tar -tzf "$archive" > "$report/libwebp-archive-members.txt"
grep -Fxq 'libwebp-1.6.0/CMakeLists.txt' "$report/libwebp-archive-members.txt"
tar -xzf "$archive" -C "$RUNNER_TEMP"
printf 'LIBWEBP_SOURCE=OFFICIAL_RELEASE_SHA256_MATCH\nSHA256=%s\n' "$expected" | tee "$report/source.txt"
# Avoid image/GUI codec dependencies for the initial standalone core library:
# no PNG/JPEG/TIFF/GLUT/GIF/SDL programs or host-tool fallback.
cmake -S "$source_dir" -B "$build_dir" -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$sdk/fire4nix-toolchain.cmake" \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr \
  -DCMAKE_INSTALL_LIBDIR=lib -DBUILD_SHARED_LIBS=ON \
  -DCMAKE_INSTALL_RPATH='$ORIGIN' \
  -DWEBP_BUILD_ANIM_UTILS=OFF -DWEBP_BUILD_CWEBP=OFF \
  -DWEBP_BUILD_DWEBP=OFF -DWEBP_BUILD_GIF2WEBP=OFF \
  -DWEBP_BUILD_IMG2WEBP=OFF -DWEBP_BUILD_VWEBP=OFF \
  -DWEBP_BUILD_WEBPINFO=OFF -DWEBP_BUILD_WEBPMUX=OFF \
  -DWEBP_BUILD_EXTRAS=OFF -DWEBP_BUILD_LIBWEBPMUX=ON \
  -DWEBP_BUILD_LIBWEBPDEMUX=ON \
  2>&1 | tee "$report/cmake-configure.log"
cmake --build "$build_dir" --parallel 2 2>&1 | tee "$report/cmake-build.log"
DESTDIR="$stage" cmake --install "$build_dir" 2>&1 | tee "$report/cmake-install.log"
for pc in libwebp libwebpmux libwebpdemux libwebpdecoder libsharpyuv glib-2.0; do
  PKG_CONFIG_PATH='' PKG_CONFIG_LIBDIR="$stage/usr/lib/pkgconfig" \
    PKG_CONFIG_SYSROOT_DIR="$stage" pkg-config --exists "$pc" || {
      echo "ERROR: $pc target .pc missing" >&2; exit 6;
    }
  PKG_CONFIG_PATH='' PKG_CONFIG_LIBDIR="$stage/usr/lib/pkgconfig" \
    PKG_CONFIG_SYSROOT_DIR="$stage" pkg-config --modversion "$pc"
done > "$report/target-pkgconfig-versions.txt"
for lib in sharpyuv webpdecoder webp webpdemux webpmux; do
  found=$(find "$stage/usr/lib" -maxdepth 1 -type f -name "lib$lib.so*" -print -quit)
  [[ -n "$found" && -s "$found" ]] || { echo "ERROR: lib$lib shared library missing" >&2; exit 6; }
  readelf -h "$found" | grep -Eq 'Class:.*ELF64'
  readelf -h "$found" | grep -Eq 'Machine:.*AArch64'
  readelf -d "$found" | grep -E 'NEEDED|SONAME|RPATH|RUNPATH' > "$report/$lib-dynamic.txt"
  # Private WebP modules must locate their sibling DSOs without putting the
  # ROCKNIX system /usr/lib ahead of the staged runtime.
  if ! grep -Eq '\((RUNPATH|RPATH)\).*\[\$ORIGIN\]' "$report/$lib-dynamic.txt"; then
    echo "ERROR: target lib$lib does not use a private-origin runtime path" >&2; exit 6;
  fi
  if readelf -d "$found" | grep -Eq 'TEXTREL|Shared library: \[libgst'; then
    echo "ERROR: invalid target dynamic dependencies in $found" >&2; exit 6;
  fi
  readelf -V "$found" > "$report/$lib-glibc-versions.txt" || true
  python3 - "$report/$lib-glibc-versions.txt" <<'PY'
import re,sys
s=open(sys.argv[1]).read()
versions=[tuple(map(int,x.split('.'))) for x in re.findall(r'Name: GLIBC_([0-9.]+)',s)]
assert all(x<=(2,41) for x in versions),versions
PY
done
cat > "$report/consumer.c" <<'C'
#include <webp/decode.h>
#include <webp/demux.h>
#include <webp/mux.h>
#include <glib.h>
#include <png.h>
int fire4nix_webp_probe(void) {
  return WebPGetDecoderVersion()>0 && WebPGetDemuxVersion()>0 &&
         WebPGetMuxVersion()>0 && g_get_prgname()!=0 &&
         png_access_version_number()>0;
}
C
"$cc" -O2 -mcpu=cortex-a35 -fPIC -shared -Wl,-z,defs \
  -I"$stage/usr/include" -I"$stage/usr/include/glib-2.0" \
  -I"$stage/usr/lib/glib-2.0/include" "$report/consumer.c" \
  -L"$stage/usr/lib" -Wl,-rpath-link,"$stage/usr/lib" \
  -Wl,--no-as-needed -lwebp -lwebpdemux -lwebpmux -lglib-2.0 -lpng16 \
  -o "$report/libfire4nix-webp-consumer.so"
readelf -h "$report/libfire4nix-webp-consumer.so" > "$report/consumer-header.txt"
readelf -d "$report/libfire4nix-webp-consumer.so" > "$report/consumer-needed.txt"
readelf -V "$report/libfire4nix-webp-consumer.so" > "$report/consumer-glibc.txt"
grep -Eq 'Machine:.*AArch64' "$report/consumer-header.txt"
for lib in libwebp.so libwebpdemux.so libwebpmux.so libglib-2.0.so libpng16.so; do
  grep -Fq "Shared library: [$lib" "$report/consumer-needed.txt" || {
    echo "ERROR: no DT_NEEDED for $lib" >&2; exit 7;
  }
done
{
  echo 'EIGHT_DEPENDENCY_STAGE=PASS_REAL_ROCKNIX_AARCH64'
  echo 'LIBWEBP_VERSION=1.6.0'
  echo 'LIBWEBP_PROVENANCE=UPSTREAM_RELEASE_BUILDROOT_SHA256'
  echo 'WEBP_GLIB_PNG_CONSUMER_LINK=PASS_REAL_AARCH64'
  echo 'GLIBC_MAX_ALLOWED=2.41'
  echo 'WEBKIT_BUILT=no'
  echo 'TARGET_EXECUTED=no'
  echo 'R36H_INSTALLABLE=no'
} | tee "$report/acceptance.txt"
cat "$report/acceptance.txt" >> "$GITHUB_STEP_SUMMARY"
