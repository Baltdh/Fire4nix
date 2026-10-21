#!/usr/bin/env bash
# Target-only libsoup3 3.6.5 on authentic ROCKNIX 20260801 RK3326 SDK.
# Disabling Meson TLS *compile-time run-test* does NOT prove HTTPS.
set -euo pipefail
[[ "$GITHUB_ACTIONS" == true && "$(id -u)" != 0 && -n "$GITHUB_WORKSPACE" ]] || exit 4
root="$GITHUB_WORKSPACE"
sdk="$root/rocknix-source/build.ROCKNIX-RK3326.aarch64/toolchain"
sysroot="$sdk/aarch64-rocknix-linux-gnu/sysroot"
cc="$sdk/bin/aarch64-rocknix-linux-gnu-gcc"
work="$root/soup3-target"
stage="$work/deps"
[[ ! -e "$work" && ! -L "$work" ]] || { echo 'ERROR: target worktree already exists';exit 4; }
mkdir -p "$work"/{source,reports,output}
report="$work/reports"
[[ "$(git -C "$root/rocknix-source" rev-parse HEAD)" == 3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb ]] || exit 4
[[ "$("$cc" -dumpmachine)" == aarch64-rocknix-linux-gnu ]] || exit 4
readelf -h "$sysroot/usr/lib/libc.so.6" | grep -Eq 'Machine:.*AArch64'
overlay="$root/fire4nix/rocknix-integration/rocknix-overlay/packages/web/libsoup3/package.mk"
hash=6891765aac3e949017945c3eaebd8cc8216df772456dc9f460976fbdb7ada234
grep -Fxq 'PKG_VERSION="3.6.5"' "$overlay"
grep -Fxq "PKG_SHA256=\"$hash\"" "$overlay"
grep -Fq -- '-Dtls_check=false' "$overlay"
grep -Fxq 'NGHTTP2_TARGET=PASS_REAL_ROCKNIX_AARCH64' \
 "$root/soup-prereqs-artifact/soup-prereqs-target/reports/acceptance.txt"
grep -Fxq 'LIBPSL_TARGET=PASS_REAL_ROCKNIX_AARCH64' \
 "$root/soup-prereqs-artifact/soup-prereqs-target/reports/acceptance.txt"
grep -Fxq 'ICU_TARGET=PASS_REAL_ROCKNIX_AARCH64' \
 "$root/icu-artifact/icu74-target/reports/acceptance.txt"
grep -Fxq 'FONTCONFIG_BUILD=PASS_REAL_ROCKNIX_AARCH64' \
 "$root/fontconfig-artifact/fontconfig-target/reports/acceptance.txt"
# Content/architecture-safe merge. No writes to device or host /usr/lib.
python3 - "$stage" \
 "$root/eight-artifact/eight-deps/stage" \
 "$root/fontconfig-artifact/fontconfig-target/stage" \
 "$root/icu-artifact/icu74-target/stage" \
 "$root/soup-prereqs-artifact/soup-prereqs-target/stage" <<'PY'
from pathlib import Path
import hashlib, shutil, subprocess, sys, re
dst=Path(sys.argv[1])
assert not dst.exists()
dst.mkdir(parents=True)
def dig(f):return hashlib.sha256(f.read_bytes()).digest()
for name in sys.argv[2:]:
 src=Path(name)
 for group in ('usr/include','usr/lib'):
  parent=src/group
  if not parent.is_dir():raise SystemExit('ERROR: absent real stage '+str(parent))
  for f in sorted(parent.rglob('*')):
   d=dst/f.relative_to(src)
   if f.is_symlink():
    link=f.readlink()
    if link.is_absolute() or '..' in link.parts: raise SystemExit('ERROR unsafe source symlink '+str(f))
    if d.is_symlink() and d.readlink()==link:continue
    if d.is_file() and dig(d)==dig(f.resolve()):continue
    if d.exists() or d.is_symlink():raise SystemExit('ERROR: differing target symlinks '+str(d))
    d.parent.mkdir(parents=True,exist_ok=True);d.symlink_to(link)
   elif f.is_dir():
    if d.is_symlink() or (d.exists() and not d.is_dir()):raise SystemExit('ERROR: dir collision '+str(d))
    d.mkdir(parents=True,exist_ok=True)
   elif f.is_file():
    if d.is_symlink():
     if d.resolve().is_file() and dig(d.resolve())==dig(f):continue
     raise SystemExit('ERROR: link/file collision '+str(d))
    if d.exists():
     if not d.is_file() or dig(d)!=dig(f):raise SystemExit('ERROR: differing target library '+str(d))
    else:
     d.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(f,d)
   else: raise SystemExit('ERROR: unsupported file '+str(f))
for soname in ('libglib-2.0.so.0','libgio-2.0.so.0','libgobject-2.0.so.0',
               'libsqlite3.so.0','libnghttp2.so.14','libpsl.so.5','libicuuc.so.74'):
 p=dst/'usr/lib'/soname
 if not p.is_file():raise SystemExit('ERROR: missing '+str(p))
 v=subprocess.run(['readelf','-h',str(p)],capture_output=True,text=True)
 if v.returncode or not re.search(r'Machine:\s+AArch64',v.stdout):
  raise SystemExit('ERROR: non-ARM64 target lib '+str(p))
for pc in ('glib-2.0','gio-2.0','gobject-2.0','sqlite3','libnghttp2','libpsl','icu-uc'):
 if not (dst/'usr/lib/pkgconfig'/f'{pc}.pc').is_file(): raise SystemExit('ERROR: missing '+pc+'.pc')
print('LIBSOUP3_DEVELOPMENT_STAGE=PASS_COLLISION_SAFE_ELF64_AARCH64')
PY
export PKG_CONFIG_PATH=''
export PKG_CONFIG_LIBDIR="$stage/usr/lib/pkgconfig:$sysroot/usr/lib/pkgconfig:$sysroot/usr/share/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$stage"
for pc in glib-2.0 gio-2.0 gobject-2.0 gio-unix-2.0 sqlite3 libnghttp2 libpsl;do
  pkg-config --exists "$pc" || { echo "ERROR: target $pc .pc missing" >&2;exit 5; }
  echo "TARGET_PC_$pc=$(pkg-config --modversion "$pc")"
done | tee "$report/versions.txt"
tarball="$work/libsoup-3.6.5.tar.xz"
curl --fail --location --silent --show-error --retry 2 \
 --proto '=https' --proto-redir '=https' --connect-timeout 15 --max-time 150 \
 'https://download.gnome.org/sources/libsoup/3.6/libsoup-3.6.5.tar.xz' -o "$tarball"
echo "$hash  $tarball" | sha256sum --check
tar -xJf "$tarball" -C "$work/source" --strip-components=1
[[ -s "$work/source/meson.build" ]] || exit 6
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
sys_root = '$stage'
pkg_config_libdir = ['$stage/usr/lib/pkgconfig', '$sysroot/usr/lib/pkgconfig']
[built-in options]
c_args = ['-mcpu=cortex-a35','-I$stage/usr/include','-I$stage/usr/include/glib-2.0','-I$stage/usr/lib/glib-2.0/include']
cpp_args = ['-mcpu=cortex-a35','-I$stage/usr/include','-I$stage/usr/include/glib-2.0','-I$stage/usr/lib/glib-2.0/include']
c_link_args = ['-L$stage/usr/lib','-Wl,-rpath-link,$stage/usr/lib']
cpp_link_args = ['-L$stage/usr/lib','-Wl,-rpath-link,$stage/usr/lib']
EOF
# Exact target opts from the immutable Fire4Nix/ROCKNIX source-verified overlay.
# Cross-compile only. -Dtls_check=false bypasses an upstream cc.run() test,
# NOT a TLS runtime probe; glib-networking/GIO TLS are still required.
if ! meson setup "$work/build" "$work/source" --cross-file "$work/cross.ini" \
  --prefix=/usr --libdir=lib --buildtype=release --wrap-mode=nodownload \
  -Dgssapi=disabled -Dntlm=disabled -Dbrotli=disabled -Dtls_check=false \
  -Dintrospection=disabled -Dvapi=disabled -Ddocs=disabled -Dtests=false \
  -Dautobahn=disabled -Dinstalled_tests=false -Dsysprof=disabled \
  -Dpkcs11_tests=disabled -Dfuzzing=disabled -Ddefault_library=shared \
  > "$report/configure.log" 2>&1;then
 echo 'LIBSOUP3_CONFIGURE=BLOCKED'
 grep -nE -B 4 -A 9 'ERROR:|Dependency .*not found|not found|Unknown options' "$report/configure.log" | head -n 150 || true
 tail -n 65 "$report/configure.log";exit 10
fi
if ! meson compile -C "$work/build" -j 2 > "$report/build.log" 2>&1;then
 echo 'LIBSOUP3_COMPILE=BLOCKED'
 grep -nE -B 4 -A 10 'FAILED:|error:|undefined reference|fatal error:' "$report/build.log" | head -n 170 || true
 tail -n 65 "$report/build.log";exit 11
fi
if ! DESTDIR="$work/output" meson install -C "$work/build" --no-rebuild > "$report/install.log" 2>&1;then
 echo 'LIBSOUP3_INSTALL=BLOCKED';tail -n 65 "$report/install.log";exit 12
fi
so="$work/output/usr/lib/libsoup-3.0.so.0"
[[ -s "$so" && -s "$work/output/usr/lib/pkgconfig/libsoup-3.0.pc" ]] || {
 echo 'ERROR: libsoup shared ELF or development metadata missing' >&2;exit 13;
}
readelf -h "$so" > "$report/elf-header.txt"
readelf -d "$so" > "$report/elf-dynamic.txt"
readelf -V "$so" > "$report/elf-versions.txt"
grep -Eq 'Class:.*ELF64' "$report/elf-header.txt"
grep -Eq 'Machine:.*AArch64' "$report/elf-header.txt"
grep -Fq 'Shared library: [libnghttp2.so.14]' "$report/elf-dynamic.txt"
grep -Fq 'Shared library: [libpsl.so.5]' "$report/elf-dynamic.txt"
python3 - "$report/elf-versions.txt" <<'PY'
from pathlib import Path
import re,sys
s=Path(sys.argv[1]).read_text()
vs=[tuple(map(int,x.split('.'))) for x in re.findall(r'Name: GLIBC_([0-9]+\.[0-9]+)',s)]
assert all(x<=(2,41) for x in vs),vs
print('LIBSOUP3_GLIBC=PASS_MAX_2_41')
PY
export PKG_CONFIG_LIBDIR="$work/output/usr/lib/pkgconfig:$stage/usr/lib/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$work/output"
pkg-config --exists 'libsoup-3.0 >= 3.0'
pkg-config --modversion libsoup-3.0 > "$report/pkg-version.txt"
{
 echo 'LIBSOUP3_VERSION=3.6.5_FIRE4NIX_OVERLAY'
 echo 'LIBSOUP3_SHA256=PASS_ROCKNIX_OVERLAY'
 echo 'LIBSOUP3_TARGET=PASS_REAL_ROCKNIX_AARCH64'
 echo 'SOUP3_TLS_RUNTIME=NOT_VERIFIED_REQUIRES_GIO_GNUTLS'
 echo 'HTTP_TLS_SMOKE=NOT_EXECUTED'
 echo 'TARGET_EXECUTED=no'
 echo 'WEBKIT_BUILT=no'
 echo 'R36H_INSTALLABLE=no'
} | tee "$report/acceptance.txt"
