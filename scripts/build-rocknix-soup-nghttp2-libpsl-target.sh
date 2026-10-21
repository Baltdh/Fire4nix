#!/usr/bin/env bash
# ROCKNIX AArch64 genuine nghttp2 1.66.0 + libpsl 0.21.5 for libsoup3.
set -euo pipefail
[[ "$GITHUB_ACTIONS" == true && "$(id -u)" != 0 && -n "$GITHUB_WORKSPACE" ]] || exit 4
root="$GITHUB_WORKSPACE"
sdk="$root/rocknix-source/build.ROCKNIX-RK3326.aarch64/toolchain"
sysroot="$sdk/aarch64-rocknix-linux-gnu/sysroot"
cc="$sdk/bin/aarch64-rocknix-linux-gnu-gcc"
icu="$root/icu-artifact/icu74-target/stage"
work="$root/soup-prereqs-target"
[[ ! -e "$work" && ! -L "$work" ]] || exit 4
mkdir -p "$work"/{nghttp2-source,psl-source,reports,stage}
stage="$work/stage"; report="$work/reports"
[[ "$(git -C "$root/rocknix-source" rev-parse HEAD)" == 3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb ]] || exit 4
[[ "$("$cc" -dumpmachine)" == aarch64-rocknix-linux-gnu ]] || exit 4
readelf -h "$sysroot/usr/lib/libc.so.6" | grep -Eq 'Machine:.*AArch64'
grep -Fxq 'ICU_TARGET=PASS_REAL_ROCKNIX_AARCH64' "$root/icu-artifact/icu74-target/reports/acceptance.txt"
readelf -h "$icu/usr/lib/libicuuc.so.74" | grep -Eq 'Machine:.*AArch64'
ngrecipe="$root/rocknix-source/packages/web/nghttp2/package.mk"
pslrecipe="$root/fire4nix/rocknix-integration/rocknix-overlay/packages/network/libpsl/package.mk"
ngsha=00ba1bdf0ba2c74b2a4fe6c8b1069dc9d82f82608af24442d430df97c6f9e631
pslsha=1dcc9ceae8b128f3c0b3f654decd0e1e891afc6ff81098f227ef260449dae208
grep -Fxq 'PKG_VERSION="1.66.0"' "$ngrecipe"
grep -Fxq "PKG_SHA256=\"$ngsha\"" "$ngrecipe"
grep -Fxq 'PKG_VERSION="0.21.5"' "$pslrecipe"
grep -Fxq "PKG_SHA256=\"$pslsha\"" "$pslrecipe"
ngfile="$work/nghttp2-1.66.0.tar.xz"
pslfile="$work/libpsl-0.21.5.tar.gz"
curl --fail --location --silent --show-error --retry 2 --proto '=https' \
  --proto-redir '=https' --connect-timeout 15 --max-time 150 \
  'https://github.com/nghttp2/nghttp2/releases/download/v1.66.0/nghttp2-1.66.0.tar.xz' -o "$ngfile"
curl --fail --location --silent --show-error --retry 2 --proto '=https' \
  --proto-redir '=https' --connect-timeout 15 --max-time 150 \
  'https://github.com/rockdaboot/libpsl/releases/download/0.21.5/libpsl-0.21.5.tar.gz' -o "$pslfile"
echo "$ngsha  $ngfile" | sha256sum --check
echo "$pslsha  $pslfile" | sha256sum --check
tar -xJf "$ngfile" -C "$work/nghttp2-source" --strip-components=1
tar -xzf "$pslfile" -C "$work/psl-source" --strip-components=1
[[ -s "$work/nghttp2-source/CMakeLists.txt" && -s "$work/psl-source/meson.build" ]] || exit 5
if ! cmake -S "$work/nghttp2-source" -B "$work/nghttp2-build" -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$sdk/fire4nix-toolchain.cmake" \
  -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_INSTALL_LIBDIR=lib \
  -DCMAKE_BUILD_TYPE=Release -DENABLE_DOC=OFF -DENABLE_FAILMALLOC=OFF \
  -DENABLE_LIB_ONLY=ON -DBUILD_SHARED_LIBS=ON -DBUILD_STATIC_LIBS=OFF \
  > "$report/ng-configure.log" 2>&1; then
  echo 'NGHTTP2_CONFIGURE=BLOCKED';tail -n 85 "$report/ng-configure.log";exit 10
fi
if ! cmake --build "$work/nghttp2-build" --parallel 2 > "$report/ng-build.log" 2>&1; then
  echo 'NGHTTP2_BUILD=BLOCKED'
  grep -nE -B 4 -A 8 'error:|FAILED|undefined reference' "$report/ng-build.log" | head -n 120 || true
  tail -n 45 "$report/ng-build.log";exit 11
fi
if ! DESTDIR="$stage" cmake --install "$work/nghttp2-build" > "$report/ng-install.log" 2>&1; then
  echo 'NGHTTP2_INSTALL=BLOCKED';tail -n 70 "$report/ng-install.log";exit 12
fi
[[ -s "$stage/usr/lib/libnghttp2.so.14" && -s "$stage/usr/lib/pkgconfig/libnghttp2.pc" ]] || {
 echo 'ERROR: required nghttp2 stage missing' >&2;exit 13;
}
readelf -h "$stage/usr/lib/libnghttp2.so.14" | grep -Eq 'Machine:.*AArch64'
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
sys_root = '$icu'
pkg_config_libdir = ['$icu/usr/lib/pkgconfig','$stage/usr/lib/pkgconfig','$sysroot/usr/lib/pkgconfig']
[built-in options]
c_args = ['-mcpu=cortex-a35','-I$icu/usr/include']
cpp_args = ['-mcpu=cortex-a35','-I$icu/usr/include']
c_link_args = ['-L$icu/usr/lib','-L$stage/usr/lib','-Wl,-rpath-link,$icu/usr/lib']
cpp_link_args = ['-L$icu/usr/lib','-L$stage/usr/lib','-Wl,-rpath-link,$icu/usr/lib']
EOF
export PKG_CONFIG_PATH='' PKG_CONFIG_SYSROOT_DIR="$icu"
export PKG_CONFIG_LIBDIR="$icu/usr/lib/pkgconfig:$stage/usr/lib/pkgconfig:$sysroot/usr/lib/pkgconfig"
pkg-config --exists 'icu-uc >= 74'
if ! meson setup "$work/psl-build" "$work/psl-source" --cross-file "$work/cross.ini" \
 --prefix=/usr --libdir=lib --buildtype=release --wrap-mode=nodownload \
 -Druntime=libicu -Dbuiltin=true -Ddocs=false -Dtests=false \
 -Ddefault_library=shared > "$report/psl-configure.log" 2>&1;then
  echo 'LIBPSL_CONFIGURE=BLOCKED'
  grep -nE -B 4 -A 9 'ERROR:|not found|Unknown options' "$report/psl-configure.log" | head -n 110 || true
  tail -n 45 "$report/psl-configure.log";exit 20
fi
if ! meson compile -C "$work/psl-build" -j 2 > "$report/psl-build.log" 2>&1; then
  echo 'LIBPSL_BUILD=BLOCKED'
  grep -nE -B 4 -A 9 'FAILED:|error:|undefined reference' "$report/psl-build.log" | head -n 125 || true
  tail -n 45 "$report/psl-build.log";exit 21
fi
if ! DESTDIR="$stage" meson install -C "$work/psl-build" --no-rebuild > "$report/psl-install.log" 2>&1; then
  echo 'LIBPSL_INSTALL=BLOCKED';tail -n 60 "$report/psl-install.log";exit 22
fi
for lib in libnghttp2.so.14 libpsl.so.5;do
 [[ -s "$stage/usr/lib/$lib" ]] || { echo "ERROR: missing target $lib" >&2;exit 23; }
 readelf -h "$stage/usr/lib/$lib" > "$report/$lib.header.txt"
 readelf -d "$stage/usr/lib/$lib" > "$report/$lib.dynamic.txt"
 readelf -V "$stage/usr/lib/$lib" > "$report/$lib.versions.txt"
 grep -Eq 'Class:.*ELF64' "$report/$lib.header.txt"
 grep -Eq 'Machine:.*AArch64' "$report/$lib.header.txt"
 if grep -Eq 'TEXTREL|Shared library: \[libgst' "$report/$lib.dynamic.txt";then exit 24;fi
done
python3 - "$report" <<'PY'
from pathlib import Path
import sys,re
for p in Path(sys.argv[1]).glob('*.versions.txt'):
 v=[tuple(map(int,x.split('.'))) for x in re.findall(r'Name: GLIBC_([0-9]+\.[0-9]+)',p.read_text())]
 assert all(x<=(2,41) for x in v),(p,v)
print('SOUP_PREREQS_GLIBC=PASS_MAX_2_41')
PY
export PKG_CONFIG_LIBDIR="$stage/usr/lib/pkgconfig:$icu/usr/lib/pkgconfig" PKG_CONFIG_SYSROOT_DIR="$stage"
for pc in libnghttp2 libpsl;do
 pkg-config --exists "$pc" || { echo "ERROR: missing $pc.pc" >&2;exit 25; }
 echo "TARGET_PC_$pc=$(pkg-config --modversion "$pc")"
done | tee "$report/versions.txt"
{
 echo 'NGHTTP2_VERSION=1.66.0_ROCKNIX'
 echo 'LIBPSL_VERSION=0.21.5_FIRE4NIX_OVERLAY'
 echo 'LIBPSL_IDNA_BACKEND=TARGET_ICU_74_1'
 echo 'SOURCES=PASS_ROCKNIX_OVERLAY_SHA256'
 echo 'NGHTTP2_TARGET=PASS_REAL_ROCKNIX_AARCH64'
 echo 'LIBPSL_TARGET=PASS_REAL_ROCKNIX_AARCH64'
 echo 'GLIBC_MAX=2.41'
 echo 'TARGET_EXECUTED=no'
 echo 'LIBSOUP_BUILT=no'
 echo 'R36H_INSTALLABLE=no'
} | tee "$report/acceptance.txt"
