#!/usr/bin/env bash
# Build effective ROCKNIX libxkbcommon 1.6.0 with genuine ARM64 libxml2,
# and prove linkage alongside the already validated ROCKNIX Wayland 1.23.1.
# Wayland-only minimal WPE runtime profile intentionally excludes XCB/X11.
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && "$(id -u)" != 0 && -n "${GITHUB_WORKSPACE:-}" ]] || {
  echo 'ERROR: non-root GitHub Actions runner required' >&2; exit 4;
}
root="$GITHUB_WORKSPACE"
[[ "$(pwd -P)" == "$root" ]] || { echo 'ERROR: use exact GitHub workspace' >&2; exit 4; }
sdk="$root/rocknix-source/build.ROCKNIX-RK3326.aarch64/toolchain"
sysroot="$sdk/aarch64-rocknix-linux-gnu/sysroot"
cc="$sdk/bin/aarch64-rocknix-linux-gnu-gcc"
work="$root/xkbcommon-target"
stage="$work/stage"
reports="$work/reports"
[[ ! -e "$work" && ! -L "$work" ]] || { echo 'ERROR: output path already occupied' >&2; exit 4; }
test "$(git -C "$root/rocknix-source" rev-parse HEAD)" = 3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb
test "$("$cc" -dumpmachine)" = aarch64-rocknix-linux-gnu
test -s "$sdk/fire4nix-toolchain.cmake"
grep -Fq "$sdk" "$sdk/fire4nix-toolchain.cmake"
readelf -h "$sysroot/usr/lib/libc.so.6" | grep -Eq 'Machine:.*AArch64'
recipe="$root/rocknix-source/projects/ROCKNIX/packages/wayland/libxkbcommon/package.mk"
grep -Fxq 'PKG_VERSION="1.6.0"' "$recipe"
grep -Fq 'PKG_DEPENDS_TARGET="toolchain xkeyboard-config libxml2 libXau libxcb"' "$recipe"
grep -Fq -- '-Dxkb-config-root=/usr/share/X11/xkb' "$recipe"
# The project recipe sets enable-x11=true; minimal Wayland WPE deliberately
# excludes X11/XCB until those genuine target libs are available and checked.
mkdir -p "$reports"
input="$root/wayland-artifact/wayland-target/stage"
[[ -d "$input/usr/lib" ]] || { echo 'ERROR: verified Wayland stage absent' >&2; exit 5; }
grep -Fxq 'WAYLAND_TARGET_BUILD=PASS_REAL_ROCKNIX_AARCH64' \
  "$root/wayland-artifact/wayland-target/reports/acceptance.txt"
grep -Fxq 'WAYLAND_LINK_CONSUMER=PASS_FOUR_REAL_AARCH64_SONAMES' \
  "$root/wayland-artifact/wayland-target/reports/acceptance.txt"
python3 "$root/fire4nix/scripts/assemble-rocknix-fontconfig-stages.py" \
  "$stage" "$input" | tee "$reports/input-merge.txt"
for lib in libwayland-client.so.0 libxml2.so.16 libglib-2.0.so.0; do
  test -s "$stage/usr/lib/$lib" || { echo "ERROR: $lib missing" >&2; exit 5; }
  readelf -h "$stage/usr/lib/$lib" | grep -Eq 'Machine:.*AArch64' || exit 5
done
export PKG_CONFIG_PATH='' PKG_CONFIG_LIBDIR="$stage/usr/lib/pkgconfig" PKG_CONFIG_SYSROOT_DIR="$stage"
for pc in libxml-2.0 wayland-client glib-2.0; do
  pkg-config --exists "$pc" || { echo "ERROR: missing $pc target metadata" >&2; exit 5; }
  echo "INPUT_PC_$pc=$(pkg-config --modversion "$pc")"
done | tee "$reports/input-versions.txt"
test "$(pkg-config --modversion wayland-client)" = 1.23.1
# Debian's original 1.6.0 release manifest gives this SHA256, independently
# corroborated by its MD5 and exactly the official xkbcommon.org tarball URL.
hash=0edc14eccdd391514458bc5f5a4b99863ed2d651e4dd761a90abf4f46ef99c2b
md5=90079ab4a0c6fa56dc75abffef9b1bc6
archive="$work/libxkbcommon-1.6.0.tar.xz"
found=0
for url in \
  'https://xkbcommon.org/download/libxkbcommon-1.6.0.tar.xz' \
  'https://ftp2.osuosl.org/pub/blfs/conglomeration/libxkbcommon/libxkbcommon-1.6.0.tar.xz' \
  'https://mirror.freedif.org/pub/blfs/conglomeration/libxkbcommon/libxkbcommon-1.6.0.tar.xz'; do
  rm -f "$archive"
  if curl --proto '=https' --proto-redir '=https' -fLsS \
    --retry 1 --connect-timeout 15 --max-time 100 "$url" -o "$archive" &&
    echo "$hash  $archive" | sha256sum -c - &&
    echo "$md5  $archive" | md5sum -c -; then
    printf 'LIBXKBCOMMON_SOURCE_URL=%s\n' "$url" | tee "$reports/source.txt"
    found=1;break
  fi
done
[[ "$found" == 1 ]] || {
  echo 'ERROR: no source matches the authenticated libxkbcommon 1.6.0 release' >&2; exit 6;
}
tar -tJf "$archive" > "$reports/archive-members.txt"
grep -Fxq 'libxkbcommon-1.6.0/meson.build' "$reports/archive-members.txt"
mkdir -p "$work/source"
tar -xJf "$archive" -C "$work/source" --strip-components=1
grep -Fq "version: '1.6.0'" "$work/source/meson.build"
echo 'LIBXKBCOMMON_SOURCE=PASS_UPSTREAM_SHA256_AND_DEBIAN_MANIFEST' | tee -a "$reports/source.txt"

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
pkg_config_libdir = ['$stage/usr/lib/pkgconfig', '$sysroot/usr/lib/pkgconfig']
[built-in options]
c_args = ['-mcpu=cortex-a35', '-I$stage/usr/include', '-I$stage/usr/include/libxml2']
cpp_args = ['-mcpu=cortex-a35', '-I$stage/usr/include', '-I$stage/usr/include/libxml2']
c_link_args = ['-L$stage/usr/lib', '-Wl,-rpath-link,$stage/usr/lib']
cpp_link_args = ['-L$stage/usr/lib', '-Wl,-rpath-link,$stage/usr/lib']
EOF
export PKG_CONFIG_PATH='' PKG_CONFIG_LIBDIR="$stage/usr/lib/pkgconfig:$sysroot/usr/lib/pkgconfig:$sysroot/usr/share/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$stage"
# WPE minimal Wayland needs core xkbcommon, not xkbcommon-x11.
# With enable-tools=false, enable-wayland=false suppresses only interactive
# diagnostic tools, not XKB operation inside a Wayland client.
if ! meson setup "$work/build" "$work/source" --cross-file "$work/cross.ini" \
  --prefix=/usr --libdir=lib --buildtype=release --wrap-mode=nodownload \
  -Ddefault_library=shared -Denable-docs=false -Denable-tools=false \
  -Denable-bash-completion=false -Denable-x11=false -Denable-wayland=false \
  -Denable-xkbregistry=true -Dxkb-config-root=/usr/share/X11/xkb \
  > "$reports/configure.log" 2>&1;then
  echo 'XKB_TARGET_CONFIGURE=BLOCKED'
  tail -n 130 "$reports/configure.log";exit 7;
fi
if ! meson compile -C "$work/build" -j 2 > "$reports/build.log" 2>&1;then
  echo 'XKB_TARGET_COMPILE=BLOCKED'
  grep -nE -B 4 -A 8 'FAILED:|error:|undefined reference|fatal error:' "$reports/build.log" | head -n 165 || true
  tail -n 80 "$reports/build.log";exit 8;
fi
if ! DESTDIR="$stage" meson install -C "$work/build" --no-rebuild \
  > "$reports/install.log" 2>&1;then
  echo 'XKB_TARGET_INSTALL=BLOCKED'
  tail -n 115 "$reports/install.log";exit 9;
fi
export PKG_CONFIG_PATH='' PKG_CONFIG_LIBDIR="$stage/usr/lib/pkgconfig" PKG_CONFIG_SYSROOT_DIR="$stage"
for pc in xkbcommon xkbregistry; do
  [[ "$(pkg-config --modversion "$pc")" == 1.6.0 ]] || {
    echo "ERROR: $pc development metadata version incorrect" >&2; exit 10;
  }
done
for name in xkbcommon xkbregistry; do
  so="$stage/usr/lib/lib$name.so.0"
  test -s "$so" || { echo "ERROR: target $name SONAME missing" >&2; exit 10; }
  readelf -h "$so" > "$reports/$name-elf-header.txt"
  readelf -d "$so" > "$reports/$name-elf-dynamic.txt"
  readelf -V "$so" > "$reports/$name-elf-versions.txt"
  grep -Eq 'Class:.*ELF64' "$reports/$name-elf-header.txt"
  grep -Eq 'Machine:.*AArch64' "$reports/$name-elf-header.txt"
  grep -Fq '(SONAME)' "$reports/$name-elf-dynamic.txt"
  if grep -Eq 'TEXTREL|Shared library: \[libgst' "$reports/$name-elf-dynamic.txt";then
    echo "ERROR: $name contains TEXTREL or GStreamer dependency" >&2;exit 10;
  fi
  python3 - "$reports/$name-elf-versions.txt" <<'PY'
import re,sys
v=[tuple(map(int,x.split('.'))) for x in re.findall(r'Name: GLIBC_([0-9.]+)',open(sys.argv[1]).read())]
assert all(x<=(2,41) for x in v),v
PY
done
grep -Fq 'Shared library: [libxml2.so.16]' "$reports/xkbregistry-elf-dynamic.txt" || {
  echo 'ERROR: xkbregistry is not linked to actual target libxml2' >&2;exit 10;
}
# AArch64 consumer references public APIs: no target code is executed in CI.
cat > "$reports/consumer.c" <<'C'
#include <xkbcommon/xkbcommon.h>
#include <xkbcommon/xkbregistry.h>
#include <wayland-client.h>
int fire4nix_wpe_keyboard_probe(void) {
  struct xkb_context *ctx=xkb_context_new(XKB_CONTEXT_NO_FLAGS);
  struct rxkb_context *registry=rxkb_context_new(RXKB_CONTEXT_NO_FLAGS);
  struct wl_display *display=wl_display_connect(NULL);
  return ctx!=0 && registry!=0 && display!=0;
}
C
"$cc" -O2 -mcpu=cortex-a35 -fPIC -shared -Wl,-z,defs \
  -I"$stage/usr/include" "$reports/consumer.c" -L"$stage/usr/lib" \
  -Wl,-rpath-link,"$stage/usr/lib" -Wl,--no-as-needed \
  -lxkbcommon -lxkbregistry -lwayland-client -lxml2 \
  -o "$reports/libfire4nix-wpe-keyboard-probe-aarch64.so"
readelf -h "$reports/libfire4nix-wpe-keyboard-probe-aarch64.so" > "$reports/consumer-header.txt"
readelf -d "$reports/libfire4nix-wpe-keyboard-probe-aarch64.so" > "$reports/consumer-dynamic.txt"
grep -Eq 'Machine:.*AArch64' "$reports/consumer-header.txt"
for name in libxkbcommon.so.0 libxkbregistry.so.0 libwayland-client.so.0 libxml2.so.16;do
  grep -Fq "Shared library: [$name]" "$reports/consumer-dynamic.txt" || {
    echo "ERROR: AArch64 keyboard consumer lacks $name" >&2;exit 11;
  }
done
{
  echo 'XKBCOMMON_BUILD=PASS_REAL_ROCKNIX_AARCH64'
  echo 'XKBCOMMON_EFFECTIVE_VERSION=1.6.0'
  echo 'XKBCOMMON_SHA256=DEBIAN_ORIGINAL_RELEASE_MATCH'
  echo 'XKBREGISTRY_LIBXML2=PASS_REAL_AARCH64'
  echo 'XKB_WAYLAND_CONSUMER=PASS_REAL_AARCH64_FOUR_SONAMES'
  echo 'XKB_X11_EXTENSION=OFF_MINIMAL_WPE_NO_XCB'
  echo 'XKB_CONFIG_ROOT=/usr/share/X11/xkb'
  echo 'XKB_RUNTIME_KEYMAP_SMOKE=NOT_EXECUTED'
  echo 'GLIBC_MAX_ALLOWED=2.41'
  echo 'WPE_WEBKIT_BUILT=no'
  echo 'TARGET_EXECUTED=no'
  echo 'R36H_INSTALLABLE=no'
} | tee "$reports/acceptance.txt"
cat "$reports/acceptance.txt" >> "$GITHUB_STEP_SUMMARY"
