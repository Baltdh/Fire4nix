#!/usr/bin/env bash
# Build ROCKNIX 20260801 fontconfig 2.17.1 with native AArch64 freetype/expat.
# Cross-compiler host only. Stage never copied to the R36H.
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && "$(id -u)" != 0 && -n "${GITHUB_WORKSPACE:-}" ]] || {
  echo 'ERROR: GitHub Actions non-root runner only' >&2; exit 4;
}
base="$GITHUB_WORKSPACE"
[[ "$(pwd -P)" == "$base" ]] || { echo 'ERROR: current working directory differs from workspace' >&2; exit 4; }
sdk="$base/rocknix-source/build.ROCKNIX-RK3326.aarch64/toolchain"
cc="$sdk/bin/aarch64-rocknix-linux-gnu-gcc"
sysroot="$sdk/aarch64-rocknix-linux-gnu/sysroot"
work="$base/fontconfig-target"
report="$work/reports"
stage="$work/stage"
[[ ! -e "$work" && ! -L "$work" ]] || { echo 'ERROR: output exists' >&2; exit 4; }
[[ "$(git -C "$base/rocknix-source" rev-parse HEAD)" == 3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb ]] || exit 4
[[ "$("$cc" -dumpmachine)" == aarch64-rocknix-linux-gnu ]] || exit 4
[[ -s "$sdk/fire4nix-toolchain.cmake" && -s "$sysroot/usr/lib/libc.so.6" ]] || exit 4
grep -Fq "$sdk" "$sdk/fire4nix-toolchain.cmake"
readelf -h "$sysroot/usr/lib/libc.so.6" | grep -Eq 'Machine:.*AArch64'
mkdir -p "$report"
choose_stage() {
  local root=$1 path
  for path in "$root/pixman-work/stage" "$root/freetype-target/stage" \
    "$root/libxml2-target/stage" "$root/stage"; do
    if [[ -d "$path/usr/lib" ]]; then printf '%s\n' "$path"; return 0; fi
  done
  echo "ERROR: no known target stage under $root" >&2
  return 5
}
pixman=$(choose_stage "$base/pixman-artifact")
freetype=$(choose_stage "$base/freetype-artifact")
xml=$(choose_stage "$base/xml-artifact")
[[ -s "$base/pixman-artifact/pixman-work/reports/acceptance.txt" ]] || exit 5
grep -Fxq 'PIXMAN_TARGET_BUILD=PASS_REAL_ROCKNIX_AARCH64' \
  "$base/pixman-artifact/pixman-work/reports/acceptance.txt"
[[ -s "$base/freetype-artifact/reports/result.txt" ||
   -s "$base/freetype-artifact/freetype-target/reports/result.txt" ]] || exit 5
[[ -s "$base/xml-artifact/libxml2-target/reports/result.txt" ||
   -s "$base/xml-artifact/reports/result.txt" ]] || exit 5
grep -Rqx --include=result.txt 'FREETYPE_BUILD=PASS_REAL_ROCKNIX_AARCH64' "$base/freetype-artifact" || exit 5
grep -Rqx --include=result.txt 'LIBXML2_BUILD=PASS_REAL_ROCKNIX_AARCH64' "$base/xml-artifact" || exit 5
python3 "$base/fire4nix/scripts/assemble-rocknix-fontconfig-stages.py" \
  "$stage" "$pixman" "$freetype" "$xml"
export PKG_CONFIG_LIBDIR="$stage/usr/lib/pkgconfig"
export PKG_CONFIG_PATH=''
export PKG_CONFIG_SYSROOT_DIR="$stage"
for pc in freetype2 libxml-2.0 pixman-1 libpng16 zlib glib-2.0; do
  pkg-config --exists "$pc" || { echo "ERROR: missing target .pc $pc" >&2; exit 5; }
  echo "$pc=$(pkg-config --modversion "$pc")"
done | tee "$report/input-target-versions.txt"
grep -Fxq 'PKG_VERSION="2.17.1"' \
  "$base/rocknix-source/packages/x11/other/fontconfig/package.mk"
fc_hash=9f5cae93f4fffc1fbc05ae99cdfc708cd60dfd6612ffc0512827025c026fa541
grep -Fxq "PKG_SHA256=\"$fc_hash\"" \
  "$base/rocknix-source/packages/x11/other/fontconfig/package.mk"
# Expat 2.7.1: import ONLY the matching AArch64 Expat files from the
# successful four-dependency cross-build. The upstream GitHub source URL
# now serves bytes with a different checksum: never waive the pinned hash.
expat_hash=354552544b8f99012e5062f7d570ec77f14b412a3ff5c7d8d0dae62c0d217c30
grep -Fxq 'PKG_VERSION="2.7.1"' "$base/rocknix-source/packages/textproc/expat/package.mk"
grep -Fxq "PKG_SHA256=\"$expat_hash\"" "$base/rocknix-source/packages/textproc/expat/package.mk"
expat_root="$base/expat-artifact"
[[ -s "$expat_root/four-reports/source-validation.txt" &&
   -s "$expat_root/four-reports/expat-abi.txt" ]] || {
  echo 'ERROR: pinned, previously verified Expat artifact reports missing' >&2; exit 7;
}
grep -Fxq 'EXPAT_ORIGINAL_SOURCE_SHA256=PASS_ROCKNIX_2_7_1' "$expat_root/four-reports/source-validation.txt"
grep -Fxq 'EXPAT_SHARED_LIBRARY=PASS_REAL_ROCKNIX_AARCH64' "$expat_root/four-reports/expat-abi.txt"
expat_stage="$expat_root/four-stage"
if [[ ! -d "$expat_stage/usr/lib" && -d "$expat_root/stage/usr/lib" ]]; then
  expat_stage="$expat_root/stage"
fi
python3 - "$expat_stage" "$stage" <<'PY'
from pathlib import Path
import hashlib, re, shutil, subprocess, sys
src,dst=map(Path,sys.argv[1:])
lib=src/'usr/lib'
if not lib.is_dir(): raise SystemExit('ERROR: Expat stage absent')
wanted=sorted(lib.glob('libexpat.so*'))
if not wanted: raise SystemExit('ERROR: Expat ELF files absent')
targets=[*wanted,lib/'pkgconfig/expat.pc',src/'usr/include/expat.h',src/'usr/include/expat_external.h']
for f in targets:
    if not f.exists() or not f.is_file(): raise SystemExit(f'ERROR: Expat file missing: {f}')
    relative=f.relative_to(src)
    out=dst/relative
    if f.is_symlink():
        link=f.readlink()
        if link.is_absolute() or '..' in link.parts: raise SystemExit(f'ERROR: unsafe Expat link {f}')
        if out.exists() or out.is_symlink(): raise SystemExit(f'ERROR: Expat destination collision {out}')
        out.parent.mkdir(parents=True,exist_ok=True)
        out.symlink_to(link)
    else:
        if out.exists() or out.is_symlink(): raise SystemExit(f'ERROR: Expat destination collision {out}')
        out.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(f,out)
for so in sorted((dst/'usr/lib').glob('libexpat.so*')):
    if so.is_symlink() or not so.is_file(): continue
    head=subprocess.run(['readelf','-h',str(so)],capture_output=True,text=True)
    if head.returncode or not re.search(r'Machine:\s+AArch64',head.stdout):
        raise SystemExit(f'ERROR: Expat is not AArch64: {so}')
print('EXPAT_ARTIFACT_IMPORT=PASS_PINNED_SHA256_AARCH64')
PY
pkg-config --exists 'expat >= 2.7.1'
readelf -h "$stage/usr/lib/libexpat.so.1" | grep -Eq 'Machine:.*AArch64'
echo 'EXPAT_TARGET=PASS_PREVIOUSLY_VERIFIED_CI_AARCH64' | tee "$report/expat-result.txt"

fc_arc="$work/fontconfig-2.17.1.tar.xz"
found=0
for url in \
 'https://ftp2.osuosl.org/pub/blfs/conglomeration/fontconfig/fontconfig-2.17.1.tar.xz' \
 'https://mirror.freedif.org/pub/blfs/conglomeration/fontconfig/fontconfig-2.17.1.tar.xz' \
 'https://mse.uk.distfiles.macports.org/fontconfig/fontconfig-2.17.1.tar.xz' \
 'https://whiteoak.umd.edu/xbmc/build-deps/sources/fontconfig-2.17.1.tar.xz' \
 'https://gitlab.freedesktop.org/api/v4/projects/890/packages/generic/fontconfig/2.17.1/fontconfig-2.17.1.tar.xz'; do
  rm -f "$fc_arc"
  if curl --proto '=https' --proto-redir '=https' --fail --silent --show-error \
      --retry 1 --connect-timeout 12 --max-time 95 "$url" -o "$fc_arc" &&
      echo "$fc_hash  $fc_arc" | sha256sum -c -; then
    echo "FONTCONFIG_SOURCE_URL=$url" | tee "$report/fontconfig-source.txt"
    found=1
    break
  fi
done
[[ "$found" == 1 ]] || { echo 'ERROR: no matching fontconfig original source SHA256' >&2; exit 10; }
mkdir -p "$work/fontconfig-source" "$work/fontconfig-build"
tar -tJf "$fc_arc" > "$report/fontconfig-archive-members.txt"
tar -xJf "$fc_arc" -C "$work/fontconfig-source" --strip-components=1
[[ -s "$work/fontconfig-source/configure" && -s "$work/fontconfig-source/src/fontconfig.h" ||
  -s "$work/fontconfig-source/configure" && -d "$work/fontconfig-source/fontconfig" ]] || {
  echo 'ERROR: fontconfig source tree unexpectedly structured' >&2; exit 10;
}
export PKG_CONFIG_LIBDIR="$stage/usr/lib/pkgconfig"
export PKG_CONFIG_PATH='' PKG_CONFIG_SYSROOT_DIR="$stage"
export CFLAGS='-O2 -mcpu=cortex-a35 -fPIC'
export CPPFLAGS="-I$stage/usr/include -I$stage/usr/include/freetype2 -I$stage/usr/include/libxml2"
export LDFLAGS="-L$stage/usr/lib -Wl,-rpath-link,$stage/usr/lib"
export FREETYPE_CFLAGS="-I$stage/usr/include/freetype2"
export FREETYPE_LIBS="-L$stage/usr/lib -lfreetype"
export EXPAT_CFLAGS="-I$stage/usr/include"
export EXPAT_LIBS="-L$stage/usr/lib -lexpat"
(
  cd "$work/fontconfig-build"
  CC="$cc" \
  AR="$sdk/bin/aarch64-rocknix-linux-gnu-ar" \
  RANLIB="$sdk/bin/aarch64-rocknix-linux-gnu-ranlib" \
  "$work/fontconfig-source/configure" \
  --host=aarch64-rocknix-linux-gnu --build="$(gcc -dumpmachine)" \
  --prefix=/usr --libdir=/usr/lib \
  --with-arch=aarch64 \
  --with-cache-dir=/storage/.cache/fontconfig \
  --with-default-fonts=/usr/share/fonts \
  --without-add-fonts \
  --disable-dependency-tracking --disable-docs \
  --disable-rpath --enable-shared \
  > "$report/fontconfig-configure.log" 2>&1
) || {
  echo 'FONTCONFIG_CONFIGURE=BLOCKED'; tail -n 120 "$report/fontconfig-configure.log"; exit 11;
}
make -C "$work/fontconfig-build" -j2 > "$report/fontconfig-build.log" 2>&1 || {
  echo 'FONTCONFIG_BUILD=BLOCKED'; tail -n 120 "$report/fontconfig-build.log"; exit 12;
}
make -C "$work/fontconfig-build" DESTDIR="$stage" install \
  > "$report/fontconfig-install.log" 2>&1 || {
  echo 'FONTCONFIG_INSTALL=BLOCKED'; tail -n 110 "$report/fontconfig-install.log"; exit 13;
}
# The distribution removes target utilities after install. This experiment
# deliberately stages them only: never execute binaries on the x86_64 host.
test -s "$stage/usr/lib/libfontconfig.so.1"
test -s "$stage/usr/lib/pkgconfig/fontconfig.pc"
readelf -h "$stage/usr/lib/libfontconfig.so.1" > "$report/fontconfig-header.txt"
readelf -d "$stage/usr/lib/libfontconfig.so.1" > "$report/fontconfig-dynamic.txt"
readelf -V "$stage/usr/lib/libfontconfig.so.1" > "$report/fontconfig-versions.txt"
grep -Eq 'Class:.*ELF64' "$report/fontconfig-header.txt"
grep -Eq 'Machine:.*AArch64' "$report/fontconfig-header.txt"
grep -Fq 'Shared library: [libfreetype.so.6]' "$report/fontconfig-dynamic.txt"
grep -Fq 'Shared library: [libexpat.so.1]' "$report/fontconfig-dynamic.txt"
if grep -Eq 'TEXTREL|Shared library: \[libgst' "$report/fontconfig-dynamic.txt"; then
  echo 'ERROR: unexpected relocation or GStreamer dependency' >&2; exit 14;
fi
python3 - "$report/fontconfig-versions.txt" <<'PY'
import re,sys
text=open(sys.argv[1]).read()
vs=[tuple(map(int,x.split('.'))) for x in re.findall(r'Name: GLIBC_([0-9.]+)',text)]
assert all(x<=(2,41) for x in vs),vs
print('FONTCONFIG_GLIBC=PASS_MAX_2_41')
PY
[[ "$(pkg-config --modversion fontconfig)" == 2.17.1 ]] || {
  echo 'ERROR: target fontconfig.pc version mismatch' >&2; exit 14;
}
for name in freetype2 expat libxml-2.0 pixman-1; do pkg-config --exists "$name"; done
cat > "$report/consumer.c" <<'C'
#include <fontconfig/fontconfig.h>
#include <ft2build.h>
#include FT_FREETYPE_H
#include <expat.h>
#include <libxml/parser.h>
#include <pixman.h>
int fire4nix_fontconfig_probe(void) {
  return FcGetVersion()>0 && FT_Library_Version!=0 &&
         XML_ExpatVersion()[0] && xmlCheckVersion!=0 &&
         pixman_version_string()[0];
}
C
# Guard against compiler constant-folding function symbols in a probe:
# --no-as-needed requires the actual ELF DT_NEEDED dependency closure.
"$cc" -O2 -mcpu=cortex-a35 -fPIC -shared -Wl,-z,defs \
  -I"$stage/usr/include" -I"$stage/usr/include/freetype2" \
  -I"$stage/usr/include/libxml2" -I"$stage/usr/include/pixman-1" \
  "$report/consumer.c" -L"$stage/usr/lib" -Wl,-rpath-link,"$stage/usr/lib" \
  -Wl,--no-as-needed \
  -lfontconfig -lfreetype -lexpat -lxml2 -lpixman-1 \
  -o "$report/libfire4nix-fontconfig-consumer.so"
readelf -h "$report/libfire4nix-fontconfig-consumer.so" > "$report/consumer-header.txt"
readelf -d "$report/libfire4nix-fontconfig-consumer.so" > "$report/consumer-dynamic.txt"
grep -Eq 'Machine:.*AArch64' "$report/consumer-header.txt"
for so in libfontconfig.so.1 libfreetype.so.6 libexpat.so.1 libxml2.so.16 libpixman-1.so.0; do
  grep -Fq "Shared library: [$so]" "$report/consumer-dynamic.txt" || {
    echo "ERROR: Fontconfig integration consumer lacks $so" >&2; exit 15;
  }
done
{
  echo 'FONTCONFIG_BUILD=PASS_REAL_ROCKNIX_AARCH64'
  echo 'FONTCONFIG_VERSION=2.17.1'
  echo 'FONTCONFIG_SOURCE=ROCKNIX_SHA256_VERIFIED'
  echo 'FONTCONFIG_GLIBC_MAX_ALLOWED=2.41'
  echo 'FONTCONFIG_FREETYPE_EXPAT_XML_PIXMAN_CONSUMER=PASS_REAL_AARCH64'
  echo 'R36H_EXECUTED=no'
  echo 'WPE_WEBKIT_BUILT=no'
  echo 'R36H_INSTALLABLE=no'
} | tee "$report/acceptance.txt"
cat "$report/acceptance.txt" >> "$GITHUB_STEP_SUMMARY"
