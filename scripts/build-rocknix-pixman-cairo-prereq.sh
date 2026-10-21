#!/usr/bin/env bash
# Compile Pixman 0.46.2 for the real ROCKNIX RK3326 AArch64 target.
# Read-only SDK, isolated stage; never execute ARM64 on an Ubuntu host.
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && "$(id -u)" != 0 && -n "${GITHUB_WORKSPACE:-}" ]] || {
  echo 'ERROR: non-root GitHub Actions environment required' >&2; exit 4;
}
root="$GITHUB_WORKSPACE"
[[ "$(pwd -P)" == "$root" ]] || { echo 'ERROR: start inside GitHub workspace' >&2; exit 4; }
sdk="$root/rocknix-source/build.ROCKNIX-RK3326.aarch64/toolchain"
sysroot="$sdk/aarch64-rocknix-linux-gnu/sysroot"
cc="$sdk/bin/aarch64-rocknix-linux-gnu-gcc"
work="$root/pixman-work"
stage="$work/stage"
reports="$work/reports"
seven="$root/seven-artifact/seven-deps"
if [[ ! -s "$seven/report/result.txt" && -s "$root/seven-artifact/report/result.txt" ]]; then
  seven="$root/seven-artifact"
fi
[[ ! -e "$work" && ! -L "$work" ]] || { echo 'ERROR: output already exists' >&2; exit 4; }
[[ -s "$seven/report/result.txt" && -d "$seven/stage/usr/lib" ]] || { echo 'ERROR: pinned seven dependency stage missing' >&2; exit 5; }
grep -Fxq 'SEVEN_DEPENDENCY_STAGE=PASS_REAL_ROCKNIX_AARCH64' "$seven/report/result.txt"
grep -Fxq 'SEVEN_CONSUMER_LINK=PASS_GLIB_GOBJECT_GIO_GMODULE' "$seven/report/result.txt"
[[ "$(git -C "$root/rocknix-source" rev-parse HEAD)" == 3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb ]] || exit 5
[[ "$("$cc" -dumpmachine)" == aarch64-rocknix-linux-gnu ]] || exit 5
[[ -s "$sdk/fire4nix-toolchain.cmake" && -s "$sysroot/usr/lib/libc.so.6" ]] || exit 5
grep -Fq "$sdk" "$sdk/fire4nix-toolchain.cmake"
readelf -h "$sysroot/usr/lib/libc.so.6" | grep -Eq 'Machine:.*AArch64'
recipe="$root/rocknix-source/packages/x11/lib/pixman/package.mk"
override="$root/rocknix-source/projects/ROCKNIX/packages/x11/lib/pixman/package.mk"
sha=d075209d18728b1ca5d0bb864aa047a262a1fde206da8a677d6af75b2ee1ae98
grep -Fxq 'PKG_VERSION="0.46.2"' "$recipe"
grep -Fxq "PKG_SHA256=\"$sha\"" "$recipe"
grep -Fq 'PIXMAN_CONFIG="-Dmmx=disabled -Dsse2=disabled -Dvmx=disabled -Darm-simd=disabled -Dneon=disabled -Diwmmxt=disabled"' "$override"
mkdir -p "$stage" "$reports"
# Copy only the verified AArch64 dependency stage, checking paths and collisions
# and reconstructing missing SONAME links from regular ELF payloads.
python3 - "$seven/stage" "$stage" <<'PY'
from pathlib import Path
import hashlib, re, shutil, subprocess, sys
src,dst=map(Path,sys.argv[1:])
if not (src/'usr/lib').is_dir(): raise SystemExit('ERROR: invalid previous stage')
for f in sorted((src/'usr').rglob('*')):
    rel=f.relative_to(src)
    out=dst/rel
    if f.is_symlink():
        target=f.readlink()
        if target.is_absolute() or '..' in target.parts: raise SystemExit(f'ERROR: unsafe symlink {rel}')
        out.parent.mkdir(parents=True,exist_ok=True)
        out.symlink_to(target)
    elif f.is_dir():
        out.mkdir(parents=True,exist_ok=True)
    elif f.is_file():
        out.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(f,out)
    else:
        raise SystemExit(f'ERROR: unexpected file {rel}')
directory=dst/'usr/lib'
for f in sorted(directory.glob('lib*.so*')):
    if f.is_symlink() or not f.is_file(): continue
    head=subprocess.run(['readelf','-h',str(f)],capture_output=True,text=True)
    if head.returncode or not re.search(r'Machine:\s+AArch64',head.stdout): continue
    dyn=subprocess.run(['readelf','-d',str(f)],capture_output=True,text=True)
    names=re.findall(r'\(SONAME\).*\[([^\]]+)\]',dyn.stdout)
    if len(names)!=1: continue
    soname=names[0]
    if not soname.startswith('lib') or '/' in soname or '..' in soname:
        raise SystemExit(f'ERROR: unsafe SONAME {soname}')
    if not f.name.startswith(soname): continue
    for link in (soname,soname.split('.so',1)[0]+'.so'):
        target=directory/link
        if target==f: continue
        if target.is_symlink() and target.readlink()==Path(f.name): continue
        if target.is_file() and not target.is_symlink() and hashlib.sha256(target.read_bytes()).digest()==hashlib.sha256(f.read_bytes()).digest(): continue
        if target.exists() or target.is_symlink(): raise SystemExit(f'ERROR: SONAME collision {target}')
        target.symlink_to(f.name)
for needed in ('libglib-2.0.so','libpng16.so','libz.so'):
    if not (directory/needed).exists(): raise SystemExit(f'ERROR: missing {needed}')
print('PIXMAN_INPUT_SEVEN_STAGE=PASS_AARCH64')
PY
archive="$work/pixman-0.46.2.tar.xz"
curl --proto '=https' --proto-redir '=https' -fLsS \
  --retry 2 --connect-timeout 15 --max-time 150 \
  'https://xorg.freedesktop.org/archive/individual/lib/pixman-0.46.2.tar.xz' \
  -o "$archive"
echo "$sha  $archive" | sha256sum -c -
tar -tJf "$archive" > "$reports/source-members.txt"
grep -Fxq 'pixman-0.46.2/meson.build' "$reports/source-members.txt"
mkdir -p "$work/source"
tar -xJf "$archive" -C "$work/source" --strip-components=1
echo 'PIXMAN_SOURCE=OFFICIAL_ROCKNIX_SHA256_MATCH' | tee "$reports/source-validation.txt"
cat > "$work/cross.ini" <<EOF
[binaries]
c = '$cc'
cpp = '$sdk/bin/aarch64-rocknix-linux-gnu-g++'
ar = '$sdk/bin/aarch64-rocknix-linux-gnu-ar'
strip = '$sdk/bin/aarch64-rocknix-linux-gnu-strip'
pkg-config = '/usr/bin/pkg-config'
[host_machine]
system = 'linux'
cpu_family = 'aarch64'
cpu = 'cortex-a35'
endian = 'little'
[properties]
sys_root = '$sysroot'
pkg_config_libdir = ['$stage/usr/lib/pkgconfig', '$sysroot/usr/lib/pkgconfig', '$sysroot/usr/share/pkgconfig']
[built-in options]
c_args = ['-mcpu=cortex-a35','-I$stage/usr/include']
c_link_args = ['-L$stage/usr/lib','-Wl,-rpath-link,$stage/usr/lib']
cpp_args = ['-mcpu=cortex-a35','-I$stage/usr/include']
cpp_link_args = ['-L$stage/usr/lib','-Wl,-rpath-link,$stage/usr/lib']
EOF
export PKG_CONFIG_PATH='' PKG_CONFIG_LIBDIR="$stage/usr/lib/pkgconfig:$sysroot/usr/lib/pkgconfig:$sysroot/usr/share/pkgconfig" PKG_CONFIG_SYSROOT_DIR="$sysroot"
# Match ROCKNIX aarch64's explicit SIMD policy. No host x86 SIMD allowed.
meson setup "$work/build" "$work/source" \
  --cross-file "$work/cross.ini" --prefix=/usr --libdir=lib \
  --buildtype=release --wrap-mode=nodownload -Ddefault_library=shared \
  -Dopenmp=disabled -Dloongson-mmi=disabled \
  -Dmmx=disabled -Dsse2=disabled -Dvmx=disabled \
  -Darm-simd=disabled -Dneon=disabled \
  -Dmips-dspr2=disabled -Dgnu-inline-asm=enabled \
  -Dtimers=false -Dgtk=disabled -Dlibpng=disabled \
  -Dtests=disabled -Ddemos=disabled \
  > "$reports/configure.log" 2>&1 || {
    echo 'PIXMAN_CONFIGURE=BLOCKED'
    tail -n 100 "$reports/configure.log"; exit 7;
  }
meson compile -C "$work/build" -j 2 > "$reports/build.log" 2>&1 || {
  echo 'PIXMAN_BUILD=BLOCKED'
  tail -n 100 "$reports/build.log"; exit 8;
}
DESTDIR="$stage" meson install -C "$work/build" --no-rebuild > "$reports/install.log" 2>&1 || {
  echo 'PIXMAN_INSTALL=BLOCKED'
  tail -n 85 "$reports/install.log"; exit 9;
}
lib=$(find "$stage/usr/lib" -maxdepth 1 -type f -name 'libpixman-1.so*' -print -quit)
[[ -n "$lib" && -s "$lib" ]] || { echo 'ERROR: actual Pixman .so missing' >&2; exit 10; }
readelf -h "$lib" > "$reports/pixman-header.txt"
readelf -d "$lib" > "$reports/pixman-dynamic.txt"
readelf -V "$lib" > "$reports/pixman-versions.txt"
grep -Eq 'Class:.*ELF64' "$reports/pixman-header.txt"
grep -Eq 'Machine:.*AArch64' "$reports/pixman-header.txt"
grep -Fq 'Shared library: [libpixman-1.so.0]' "$reports/pixman-dynamic.txt" && {
  echo 'ERROR: self-reference in Pixman DT_NEEDED' >&2; exit 10;
}
grep -Fq '(SONAME)' "$reports/pixman-dynamic.txt"
if grep -Eq 'TEXTREL|Shared library: \[libgst' "$reports/pixman-dynamic.txt"; then
  echo 'ERROR: forbidden media dependency or TEXTREL' >&2; exit 10;
fi
python3 - "$reports/pixman-versions.txt" <<'PY'
import re,sys
data=open(sys.argv[1]).read()
v=[tuple(map(int,x.split('.'))) for x in re.findall(r'Name: GLIBC_([0-9.]+)',data)]
assert all(x<=(2,41) for x in v),v
print('PIXMAN_GLIBC=PASS_MAX_2_41')
PY
export PKG_CONFIG_LIBDIR="$stage/usr/lib/pkgconfig" PKG_CONFIG_PATH='' PKG_CONFIG_SYSROOT_DIR="$stage"
[[ "$(pkg-config --modversion pixman-1)" == 0.46.2 ]] || { echo 'ERROR: target pixman-1.pc has wrong version' >&2; exit 10; }
for pc in glib-2.0 libpng16 zlib; do pkg-config --exists "$pc" || exit 10; done
cat > "$reports/pixman-consumer.c" <<'C'
#include <pixman.h>
#include <glib.h>
#include <png.h>
int fire4nix_pixman_probe(void) {
  return pixman_version_string()[0] != 0 && g_get_monotonic_time() >= 0 &&
         png_access_version_number() > 0;
}
C
"$cc" -O2 -mcpu=cortex-a35 -fPIC -shared -Wl,-z,defs \
  -I"$stage/usr/include/pixman-1" -I"$stage/usr/include" \
  -I"$stage/usr/include/glib-2.0" -I"$stage/usr/lib/glib-2.0/include" \
  "$reports/pixman-consumer.c" -L"$stage/usr/lib" \
  -Wl,-rpath-link,"$stage/usr/lib" -Wl,--no-as-needed \
  -lpixman-1 -lglib-2.0 -lpng16 -lz \
  -o "$reports/libfire4nix-pixman-cairo-preflight.so"
readelf -h "$reports/libfire4nix-pixman-cairo-preflight.so" > "$reports/consumer-header.txt"
readelf -d "$reports/libfire4nix-pixman-cairo-preflight.so" > "$reports/consumer-dynamic.txt"
readelf -V "$reports/libfire4nix-pixman-cairo-preflight.so" > "$reports/consumer-versions.txt"
grep -Eq 'Machine:.*AArch64' "$reports/consumer-header.txt"
for so in libpixman-1.so.0 libglib-2.0.so.0 libpng16.so.16 libz.so.1; do
  grep -Fq "Shared library: [$so]" "$reports/consumer-dynamic.txt" || {
    echo "ERROR: target consumer not linked to $so" >&2; exit 11;
  }
done
{
  echo 'PIXMAN_TARGET_BUILD=PASS_REAL_ROCKNIX_AARCH64'
  echo 'PIXMAN_VERSION=0.46.2'
  echo 'PIXMAN_SHA256=ROCKNIX_RECIPE_VERIFIED'
  echo 'PIXMAN_GLIB_PNG_ZLIB_CONSUMER=PASS_AARCH64_REAL_SONAMES'
  echo 'GLIBC_MAX_ALLOWED=2.41'
  echo 'WPE_WEBKIT_BUILT=no'
  echo 'TARGET_EXECUTED=no'
  echo 'R36H_INSTALLABLE=no'
} | tee "$reports/acceptance.txt"
cat "$reports/acceptance.txt" >> "$GITHUB_STEP_SUMMARY"
