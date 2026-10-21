#!/usr/bin/env bash
# Build only private ROCKNIX AArch64 EGL/GLES development stage.
# Source from ROCKNIX's libglvnd 1.7.0 recipe, no Ubuntu target libraries.
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && "$(id -u)" != 0 && -n "${GITHUB_WORKSPACE:-}" ]] ||
  { echo 'ERROR: non-root GitHub Actions runner only' >&2; exit 4; }
root="$GITHUB_WORKSPACE"
sdk="$root/rocknix-source/build.ROCKNIX-RK3326.aarch64/toolchain"
sysroot="$sdk/aarch64-rocknix-linux-gnu/sysroot"
work="$root/glvnd-target"
[[ ! -e "$work" && ! -L "$work" ]] || { echo 'ERROR: existing stage' >&2; exit 4; }
mkdir -p "$work"/{source,reports,stage}
[[ "$(git -C "$root/rocknix-source" rev-parse HEAD)" == 3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb ]] || exit 4
cc="$sdk/bin/aarch64-rocknix-linux-gnu-gcc"
[[ "$("$cc" -dumpmachine)" == aarch64-rocknix-linux-gnu ]] || exit 4
readelf -h "$sysroot/usr/lib/libc.so.6" | grep -Eq 'Machine:.*AArch64'
recipe="$root/rocknix-source/packages/graphics/libglvnd/package.mk"
project="$root/rocknix-source/projects/ROCKNIX/packages/graphics/libglvnd/package.mk"
hash=073e7292788d4d3eeb45ea6c7bdcce9bfdb3b3eef8d7dbd47f2f30dce046ef98
grep -Fxq 'PKG_VERSION="1.7.0"' "$recipe"
grep -Fxq "PKG_SHA256=\"$hash\"" "$recipe"
grep -Fxq 'PKG_VERSION="1.7.0"' "$project"
archive="$work/libglvnd-1.7.0.tar.gz"
curl --fail --location --silent --show-error --retry 2 \
  --proto '=https' --proto-redir '=https' --connect-timeout 12 --max-time 140 \
  'https://github.com/NVIDIA/libglvnd/archive/v1.7.0.tar.gz' --output "$archive"
echo "$hash  $archive" | sha256sum --check
tar -xzf "$archive" -C "$work/source" --strip-components=1
[[ -s "$work/source/meson.build" && -s "$work/source/meson_options.txt" ]] ||
  { echo 'ERROR: unexpected libglvnd source layout' >&2; exit 5; }
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
pkg_config_libdir = ['$sysroot/usr/lib/pkgconfig', '$sysroot/usr/share/pkgconfig']
[built-in options]
c_args = ['-mcpu=cortex-a35']
cpp_args = ['-mcpu=cortex-a35']
EOF
export PKG_CONFIG_PATH='' PKG_CONFIG_LIBDIR="$sysroot/usr/lib/pkgconfig:$sysroot/usr/share/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$sysroot"
# WPE minimal Wayland exploration: build EGL/GLES2 dispatch and real headers,
# but no X11/GLX; does not reproduce entire ROCKNIX project recipe.
if ! meson setup "$work/build" "$work/source" --cross-file "$work/cross.ini" \
  --prefix=/usr --libdir=lib --buildtype=release --wrap-mode=nodownload \
  -Ddefault_library=shared -Dx11=disabled -Dglx=disabled \
  -Degl=true -Dgles1=false -Dgles2=true -Dheaders=true -Dasm=disabled \
  > "$work/reports/configure.log" 2>&1; then
    echo 'GLVND_EGL_CONFIGURE=BLOCKED_REAL_SDK'
    grep -nE -B 5 -A 10 'ERROR:|not found|Unknown options|Dependency' "$work/reports/configure.log" | head -n 120 || true
    tail -n 40 "$work/reports/configure.log"
    exit 10
fi
if ! meson compile -C "$work/build" -j 2 > "$work/reports/build.log" 2>&1; then
    echo 'GLVND_EGL_BUILD=BLOCKED'
    grep -nE -B 5 -A 10 'FAILED:|error:|undefined reference' "$work/reports/build.log" | head -n 145 || true
    tail -n 45 "$work/reports/build.log"
    exit 11
fi
if ! DESTDIR="$work/stage" meson install -C "$work/build" --no-rebuild \
  > "$work/reports/install.log" 2>&1; then
    echo 'GLVND_EGL_INSTALL=BLOCKED'
    tail -n 50 "$work/reports/install.log"
    exit 12
fi
for head in EGL/egl.h EGL/eglext.h EGL/eglplatform.h GLES2/gl2.h KHR/khrplatform.h; do
  [[ -s "$work/stage/usr/include/$head" ]] || {
    echo "ERROR: expected real EGL/GLES2 header unavailable in GLVND stage $head" >&2; exit 13;
  }
done
for lib in libEGL.so.1 libGLESv2.so.2; do
  path="$work/stage/usr/lib/$lib"
  [[ -s "$path" ]] || { echo "ERROR: target library missing $lib" >&2; exit 13; }
  readelf -h "$path" | grep -Eq 'Machine:.*AArch64'
done
for lib in libEGL.so.1 libGLESv2.so.2; do
  readelf -d "$work/stage/usr/lib/$lib" > "$work/reports/$lib-needed.txt"
  readelf -V "$work/stage/usr/lib/$lib" > "$work/reports/$lib-versions.txt"
  if grep -Eq 'TEXTREL|Shared library: \[libgst' "$work/reports/$lib-needed.txt"; then
    echo "ERROR: forbidden dependency in $lib" >&2; exit 14;
  fi
done
python3 - "$work/reports" <<'PY'
from pathlib import Path
import re,sys
for p in Path(sys.argv[1]).glob('*-versions.txt'):
    s=p.read_text()
    v=[tuple(map(int,x.split('.'))) for x in re.findall(r'Name: GLIBC_([0-9]+\.[0-9]+)',s)]
    assert all(x<=(2,41) for x in v), (p,v)
print('GLVND_GLIBC=PASS_MAX_2_41')
PY
for pc in egl glesv2; do
  [[ -s "$work/stage/usr/lib/pkgconfig/$pc.pc" ]] || {
    echo "ERROR: missing target pkgconfig $pc" >&2; exit 14;
  }
done
{
  echo 'GLVND_VERSION=1.7.0_ROCKNIX_EFFECTIVE'
  echo 'GLVND_SOURCE=PASS_ORIGINAL_ROCKNIX_SHA256'
  echo 'GLVND_EGL_GLES_HEADERS=PASS_REAL_TARGET_STAGE'
  echo 'GLVND_EGL_GLES_SHARED=PASS_REAL_ROCKNIX_AARCH64'
  echo 'GLVND_X11_GLX_PROFILE=OFF_WPE_MINIMAL'
  echo 'TARGET_EXECUTED=no'
  echo 'GRAPHICS_RENDERING_PROVEN=no'
  echo 'WEBKIT_BUILT=no'
  echo 'R36H_INSTALLABLE=no'
} | tee "$work/reports/result.txt"
