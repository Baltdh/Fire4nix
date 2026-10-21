#!/usr/bin/env bash
# Test target-only Epoxy 1.5.10 against genuine ROCKNIX RK3326 SDK EGL headers.
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && "$(id -u)" != 0 && -n "${GITHUB_WORKSPACE:-}" ]] || {
  echo 'ERROR: GitHub non-root runner only' >&2; exit 4;
}
root="$GITHUB_WORKSPACE"
sdk="$root/rocknix-source/build.ROCKNIX-RK3326.aarch64/toolchain"
sysroot="$sdk/aarch64-rocknix-linux-gnu/sysroot"
cc="$sdk/bin/aarch64-rocknix-linux-gnu-gcc"
work="$root/libepoxy-target"
glvnd="$root/glvnd-artifact/glvnd-target/stage"
[[ ! -e "$work" && ! -L "$work" ]] || { echo 'ERROR: output already exists' >&2; exit 4; }
mkdir -p "$work"/{source,reports,stage}
[[ "$(git -C "$root/rocknix-source" rev-parse HEAD)" == 3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb ]] || exit 4
[[ "$("$cc" -dumpmachine)" == aarch64-rocknix-linux-gnu ]] || exit 4
readelf -h "$sysroot/usr/lib/libc.so.6" | grep -Eq 'Machine:.*AArch64'
recipe="$root/rocknix-source/packages/graphics/libepoxy/package.mk"
override="$root/rocknix-source/projects/ROCKNIX/packages/graphics/libepoxy/package.mk"
hash=a7ced37f4102b745ac86d6a70a9da399cc139ff168ba6b8002b4d8d43c900c15
grep -Fxq 'PKG_VERSION="1.5.10"' "$recipe"
grep -Fxq "PKG_SHA256=\"$hash\"" "$recipe"
grep -Fxq 'PKG_VERSION="1.5.10"' "$override"
grep -Fxq 'GLVND_EGL_GLES_HEADERS=PASS_REAL_TARGET_STAGE'   "$root/glvnd-artifact/glvnd-target/reports/result.txt" || {
  echo 'ERROR: libglvnd stage has not passed real ROCKNIX target checks' >&2; exit 5;
}
for header in EGL/egl.h EGL/eglext.h EGL/eglplatform.h GLES2/gl2.h KHR/khrplatform.h; do
  [[ -s "$glvnd/usr/include/$header" ]] || { echo "ERROR: true target GLVND header missing: $header" >&2; exit 5; }
done
for lib in libEGL.so.1 libGLESv2.so.2; do
  [[ -s "$glvnd/usr/lib/$lib" ]] && readelf -h "$glvnd/usr/lib/$lib" | grep -Eq 'Machine:.*AArch64' || {
    echo "ERROR: genuine libglvnd AArch64 $lib absent" >&2; exit 5;
  }
done
echo 'EGL_SOURCE_STAGE=GLVND_1_7_0_ROCKNIX_AARCH64_VERIFIED' >> "$work/reports/egl-sysroot-census.txt"
cat > "$work/reports/egl-sysroot-census.txt" <<EOF
SDK_CHECKOUT=ROCKNIX_20260801
SDK_GCC_TARGET=aarch64-rocknix-linux-gnu
LIBEPOXY_VERSION=1.5.10
EGL_TARGET_PROBE=START
EOF
for head in EGL/egl.h EGL/eglext.h GLES2/gl2.h KHR/khrplatform.h; do
  if [[ -s "$sysroot/usr/include/$head" ]]; then
    echo "TARGET_HEADER_$head=FOUND" >> "$work/reports/egl-sysroot-census.txt"
  else
    echo "TARGET_HEADER_$head=MISSING" >> "$work/reports/egl-sysroot-census.txt"
  fi
done
for lib in libEGL.so libGLESv2.so; do
  if [[ -e "$sysroot/usr/lib/$lib" ]]; then
    echo "TARGET_LIBRARY_$lib=FOUND" >> "$work/reports/egl-sysroot-census.txt"
  else
    echo "TARGET_LIBRARY_$lib=MISSING" >> "$work/reports/egl-sysroot-census.txt"
  fi
done
cat "$work/reports/egl-sysroot-census.txt"
archive="$work/libepoxy-1.5.10.tar.gz"
curl --fail --location --silent --show-error --retry 2 \
  --proto '=https' --proto-redir '=https' --connect-timeout 15 --max-time 120 \
  'https://github.com/anholt/libepoxy/archive/1.5.10.tar.gz' --output "$archive"
echo "$hash  $archive" | sha256sum --check
tar -xzf "$archive" -C "$work/source" --strip-components=1
[[ -s "$work/source/meson.build" && -s "$work/source/meson_options.txt" ]] || {
  echo 'ERROR: libepoxy source is not correct 1.5.10 Meson tree' >&2; exit 5;
}
echo 'LIBEPOXY_SOURCE_SHA256=PASS_ROCKNIX_GENERIC_RECIPE' >> "$work/reports/egl-sysroot-census.txt"
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
sys_root = '$glvnd'
pkg_config_libdir = ['$glvnd/usr/lib/pkgconfig', '$sysroot/usr/lib/pkgconfig', '$sysroot/usr/share/pkgconfig']
[built-in options]
c_args = ['-mcpu=cortex-a35', '-I$glvnd/usr/include']
c_link_args = ['-L$glvnd/usr/lib', '-Wl,-rpath-link,$glvnd/usr/lib']
cpp_args = ['-mcpu=cortex-a35', '-I$glvnd/usr/include']
cpp_link_args = ['-L$glvnd/usr/lib', '-Wl,-rpath-link,$glvnd/usr/lib']
EOF
export PKG_CONFIG_PATH='' PKG_CONFIG_LIBDIR="$glvnd/usr/lib/pkgconfig:$sysroot/usr/lib/pkgconfig:$sysroot/usr/share/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$glvnd"
# First WPE minimal profile: EGL on (Wayland GPU path), no X11/GLX and no
# Ubuntu dev libraries. Do not claim equivalence with ROCKNIX full wl option.
if ! meson setup "$work/build" "$work/source" --cross-file "$work/cross.ini" \
  --prefix=/usr --libdir=lib --buildtype=release --wrap-mode=nodownload \
  -Ddefault_library=shared -Dtests=false -Ddocs=false \
  -Degl=yes -Dglx=no -Dx11=false > "$work/reports/configure.log" 2>&1; then
  echo 'LIBEPOXY_EGL_CONFIGURE=BLOCKED_REAL_ROCKNIX_SDK'
  grep -nE -B 4 -A 8 'ERROR:|Dependency .*not found|not found|Unknown options' "$work/reports/configure.log" | head -n 110 || true
  tail -n 45 "$work/reports/configure.log"
  exit 10
fi
echo 'LIBEPOXY_EGL_CONFIGURE=PASS_TARGET_SDK'
if ! meson compile -C "$work/build" -j 2 > "$work/reports/build.log" 2>&1; then
  echo 'LIBEPOXY_EGL_BUILD=BLOCKED'
  grep -nE -B 4 -A 9 'FAILED:|fatal error:|error:|undefined reference' "$work/reports/build.log" | head -n 130 || true
  tail -n 45 "$work/reports/build.log"
  exit 11
fi
if ! DESTDIR="$work/stage" meson install -C "$work/build" --no-rebuild > "$work/reports/install.log" 2>&1; then
  echo 'LIBEPOXY_INSTALL=BLOCKED'
  tail -n 50 "$work/reports/install.log"
  exit 12
fi
lib="$work/stage/usr/lib/libepoxy.so.0"
[[ -s "$lib" && -s "$work/stage/usr/lib/pkgconfig/epoxy.pc" ]] || {
  echo 'ERROR: missing actual libepoxy.so.0 or epoxy.pc' >&2; exit 13;
}
readelf -h "$lib" > "$work/reports/elf-header.txt"
readelf -d "$lib" > "$work/reports/elf-dynamic.txt"
readelf -V "$lib" > "$work/reports/elf-versions.txt"
grep -Eq 'Class:.*ELF64' "$work/reports/elf-header.txt"
grep -Eq 'Machine:.*AArch64' "$work/reports/elf-header.txt"
grep -Eq 'Type:.*DYN' "$work/reports/elf-header.txt"
if grep -Eq 'TEXTREL|Shared library: \[libgst' "$work/reports/elf-dynamic.txt"; then
  echo 'ERROR: forbidden target GStreamer or TEXTREL' >&2; exit 14;
fi
python3 - "$work/reports/elf-versions.txt" <<'PY'
from pathlib import Path
import re,sys
s=Path(sys.argv[1]).read_text()
v=[tuple(map(int,x.split('.'))) for x in re.findall(r'Name: GLIBC_([0-9]+\.[0-9]+)',s)]
assert all(x<=(2,41) for x in v),v
print('LIBEPOXY_GLIBC=PASS_MAX_2_41')
PY
export PKG_CONFIG_LIBDIR="$work/stage/usr/lib/pkgconfig" PKG_CONFIG_SYSROOT_DIR="$work/stage"
pkg-config --exists 'epoxy >= 1.5.4'
pkg-config --modversion epoxy > "$work/reports/epoxy-version.txt"
cat > "$work/consumer.c" <<'C'
#include <epoxy/egl.h>
int fire4nix_epoxy_probe(void) {
    return epoxy_has_egl_extension((EGLDisplay)0, "EGL_KHR_image_base");
}
C
"$cc" -O2 -mcpu=cortex-a35 -shared -fPIC -Wl,-z,defs \
  -I"$work/stage/usr/include" -I"$glvnd/usr/include" "$work/consumer.c" \
  -L"$work/stage/usr/lib" -Wl,-rpath-link,"$work/stage/usr/lib" \
  -lepoxy -o "$work/libepoxy-consumer-aarch64.so"
readelf -h "$work/libepoxy-consumer-aarch64.so" > "$work/reports/consumer-header.txt"
readelf -d "$work/libepoxy-consumer-aarch64.so" > "$work/reports/consumer-dynamic.txt"
grep -Eq 'Machine:.*AArch64' "$work/reports/consumer-header.txt"
grep -Fq 'Shared library: [libepoxy.so.0]' "$work/reports/consumer-dynamic.txt"
{
 echo 'LIBEPOXY_VERSION=1.5.10_ROCKNIX_EFFECTIVE'
 echo 'LIBEPOXY_EGL_HEADERS=FROM_VERIFIED_LIBGLVND_1.7.0_TARGET'
 echo 'LIBEPOXY_EGL_BUILD=PASS_REAL_ROCKNIX_AARCH64'
 echo 'LIBEPOXY_GLX_X11_PROFILE=OFF_WPE_MINIMAL'
 echo 'LIBEPOXY_CONSUMER_LINK=PASS_ELF64_AARCH64'
 echo 'LIBEPOXY_GLIBC_MAX_ALLOWED=2.41'
 echo 'TARGET_EXECUTED=no'
 echo 'WEBKIT_BUILT=no'
 echo 'R36H_INSTALLABLE=no'
} | tee "$work/reports/result.txt"
