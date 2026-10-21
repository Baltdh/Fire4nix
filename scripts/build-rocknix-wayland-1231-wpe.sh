#!/usr/bin/env bash
# Build target Wayland 1.23.1 + an isolated native wayland-scanner 1.23.1.
# The scanner runs only on Ubuntu; the AArch64 libraries are link-tested,
# never executed. Do not install to R36H or modify the ROCKNIX SDK sysroot.
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && "$(id -u)" != 0 && -n "${GITHUB_WORKSPACE:-}" ]] || {
  echo 'ERROR: non-root GitHub Actions runner required' >&2; exit 4;
}
base="$GITHUB_WORKSPACE"
[[ "$(pwd -P)" == "$base" ]] || { echo 'ERROR: use original workspace' >&2; exit 4; }
sdk="$base/rocknix-source/build.ROCKNIX-RK3326.aarch64/toolchain"
sysroot="$sdk/aarch64-rocknix-linux-gnu/sysroot"
cc="$sdk/bin/aarch64-rocknix-linux-gnu-gcc"
work="$base/wayland-target"
stage="$work/stage"
reports="$work/reports"
host_prefix="$work/host-tools"
[[ ! -e "$work" && ! -L "$work" ]] || { echo 'ERROR: existing output path' >&2; exit 4; }
test "$(git -C "$base/rocknix-source" rev-parse HEAD)" = 3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb
test "$("$cc" -dumpmachine)" = aarch64-rocknix-linux-gnu
test -s "$sdk/fire4nix-toolchain.cmake"
test -s "$sysroot/usr/lib/libc.so.6"
grep -Fq "$sdk" "$sdk/fire4nix-toolchain.cmake"
readelf -h "$sysroot/usr/lib/libc.so.6" | grep -Eq 'Machine:.*AArch64'
recipe="$base/rocknix-source/projects/ROCKNIX/packages/wayland/wayland/package.mk"
grep -Fxq 'PKG_VERSION="1.23.1"' "$recipe"
grep -Fq 'PKG_MESON_OPTS_TARGET="-Dlibraries=true' "$recipe"
grep -Fq -- '-Dscanner=false' "$recipe"
mkdir -p "$reports"
input="$base/fontconfig-artifact/fontconfig-target/stage"
[[ -d "$input/usr/lib" ]] || { echo 'ERROR: pinned Fontconfig build stage missing' >&2; exit 5; }
grep -Fxq 'FONTCONFIG_BUILD=PASS_REAL_ROCKNIX_AARCH64' \
  "$base/fontconfig-artifact/fontconfig-target/reports/acceptance.txt"
python3 "$base/fire4nix/scripts/assemble-rocknix-fontconfig-stages.py" \
  "$stage" "$input" | tee "$reports/input-merge.txt"
for lib in "$stage/usr/lib/libffi.a" "$stage/usr/lib/libexpat.so.1" \
  "$stage/usr/lib/libxml2.so.16" "$stage/usr/lib/pkgconfig/libffi.pc"; do
  [[ -s "$lib" ]] || { echo "ERROR: required genuine target library missing: $lib" >&2; exit 5; }
done
export PKG_CONFIG_PATH='' PKG_CONFIG_LIBDIR="$stage/usr/lib/pkgconfig" PKG_CONFIG_SYSROOT_DIR="$stage"
for pc in libffi expat libxml-2.0 glib-2.0; do
  pkg-config --exists "$pc" || { echo "ERROR: target $pc.pc absent" >&2; exit 5; }
  echo "TARGET_PC_$pc=$(pkg-config --modversion "$pc")"
done | tee "$reports/input-pc.txt"
# Project override has no SHA256. Use the author-signed release announcement,
# independently corroborated by Buildroot, without silently switching to 1.24.
hash=864fb2a8399e2d0ec39d56e9d9b753c093775beadc6022ce81f441929a81e5ed
archive="$work/wayland-1.23.1.tar.xz"
verified=0
for url in \
 'https://gitlab.freedesktop.org/wayland/wayland/-/releases/1.23.1/downloads/wayland-1.23.1.tar.xz' \
 'https://ftp2.osuosl.org/pub/blfs/conglomeration/wayland/wayland-1.23.1.tar.xz' \
 'https://mirrors.dotsrc.org/slackware/slackware64/testing/source/graphics-updates/wayland/wayland-1.23.1.tar.xz'; do
  rm -f "$archive"
  if curl -fLsS --proto '=https' --proto-redir '=https' \
    --retry 1 --connect-timeout 12 --max-time 90 "$url" -o "$archive" &&
    echo "$hash  $archive" | sha256sum -c -; then
    echo "WAYLAND_SOURCE_URL=$url" | tee "$reports/source.txt"
    verified=1; break
  fi
done
[[ "$verified" == 1 ]] || { echo 'ERROR: official Wayland source hash mismatch/all mirrors unavailable' >&2; exit 6; }
tar -tJf "$archive" > "$reports/archive-members.txt"
grep -Fxq 'wayland-1.23.1/meson.build' "$reports/archive-members.txt"
mkdir -p "$work/source"
tar -xJf "$archive" -C "$work/source" --strip-components=1
grep -Fq "version: '1.23.1'" "$work/source/meson.build"
printf 'WAYLAND_SOURCE=PASS_ORIGINAL_RELEASE_SHA256\nSHA256=%s\n' "$hash" | tee -a "$reports/source.txt"

# The original Wayland Meson project explicitly needs a *native* scanner
# even with -Dscanner=false, because protocol headers must be generated.
# Build scanner from the SAME verified source as a host-only code generator.
meson setup "$work/host-build" "$work/source" --prefix="$host_prefix" --libdir=lib \
  --buildtype=release --wrap-mode=nodownload \
  -Dlibraries=false -Dscanner=true -Dtests=false -Ddocumentation=false \
  -Ddtd_validation=false > "$reports/host-configure.log" 2>&1 || {
    echo 'WAYLAND_NATIVE_SCANNER_CONFIGURE=BLOCKED'
    tail -n 105 "$reports/host-configure.log"; exit 7;
  }
meson compile -C "$work/host-build" -j 2 > "$reports/host-build.log" 2>&1 || {
  echo 'WAYLAND_NATIVE_SCANNER_BUILD=BLOCKED'
  tail -n 110 "$reports/host-build.log"; exit 8;
}
meson install -C "$work/host-build" --no-rebuild > "$reports/host-install.log" 2>&1 || {
  echo 'WAYLAND_NATIVE_SCANNER_INSTALL=BLOCKED'
  tail -n 90 "$reports/host-install.log"; exit 9;
}
test -x "$host_prefix/bin/wayland-scanner"
[[ "$("$host_prefix/bin/wayland-scanner" --version)" == wayland-scanner\ 1.23.1 ]] || {
  echo 'ERROR: native scanner version does not match source' >&2; exit 9;
}
test -s "$host_prefix/lib/pkgconfig/wayland-scanner.pc"
echo 'WAYLAND_NATIVE_SCANNER=PASS_HOST_ONLY_1_23_1' | tee "$reports/host-result.txt"

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
c_args = ['-mcpu=cortex-a35', '-I$stage/usr/include']
c_link_args = ['-L$stage/usr/lib', '-Wl,-rpath-link,$stage/usr/lib']
cpp_args = ['-mcpu=cortex-a35', '-I$stage/usr/include']
cpp_link_args = ['-L$stage/usr/lib', '-Wl,-rpath-link,$stage/usr/lib']
EOF
cat > "$work/native.ini" <<EOF
[binaries]
pkg-config = '/usr/bin/pkg-config'
[properties]
pkg_config_libdir = ['$host_prefix/lib/pkgconfig', '/usr/lib/x86_64-linux-gnu/pkgconfig', '/usr/share/pkgconfig']
EOF
export PKG_CONFIG_LIBDIR="$stage/usr/lib/pkgconfig:$sysroot/usr/lib/pkgconfig:$sysroot/usr/share/pkgconfig"
export PKG_CONFIG_PATH='' PKG_CONFIG_SYSROOT_DIR="$stage"
meson setup "$work/target-build" "$work/source" \
  --cross-file "$work/cross.ini" --native-file "$work/native.ini" \
  --prefix=/usr --libdir=lib --buildtype=release --wrap-mode=nodownload \
  -Ddefault_library=shared -Dlibraries=true -Dscanner=false \
  -Dtests=false -Ddocumentation=false -Ddtd_validation=false \
  > "$reports/target-configure.log" 2>&1 || {
    echo 'WAYLAND_CROSS_CONFIGURE=BLOCKED'
    tail -n 125 "$reports/target-configure.log"; exit 10;
  }
meson compile -C "$work/target-build" -j 2 > "$reports/target-build.log" 2>&1 || {
  echo 'WAYLAND_CROSS_COMPILE=BLOCKED'
  tail -n 125 "$reports/target-build.log"; exit 11;
}
DESTDIR="$stage" meson install -C "$work/target-build" --no-rebuild > "$reports/target-install.log" 2>&1 || {
  echo 'WAYLAND_CROSS_INSTALL=BLOCKED'
  tail -n 95 "$reports/target-install.log"; exit 12;
}
export PKG_CONFIG_LIBDIR="$stage/usr/lib/pkgconfig" PKG_CONFIG_PATH='' PKG_CONFIG_SYSROOT_DIR="$stage"
for pc in wayland-client wayland-server wayland-cursor wayland-egl; do
  [[ "$(pkg-config --modversion "$pc")" == 1.23.1 ]] || {
    echo "ERROR: $pc package missing or wrong version" >&2; exit 13;
  }
done
for name in wayland-client wayland-server wayland-cursor wayland-egl; do
  so=$(find "$stage/usr/lib" -maxdepth 1 -type f -name "lib$name.so.*" -print -quit)
  [[ -n "$so" && -s "$so" ]] || { echo "ERROR: missing target lib$name DSO" >&2; exit 13; }
  readelf -h "$so" > "$reports/$name-elf-header.txt"
  readelf -d "$so" > "$reports/$name-dynamic.txt"
  readelf -V "$so" > "$reports/$name-versions.txt"
  grep -Eq 'Class:.*ELF64' "$reports/$name-elf-header.txt"
  grep -Eq 'Machine:.*AArch64' "$reports/$name-elf-header.txt"
  grep -Fq '(SONAME)' "$reports/$name-dynamic.txt"
  if grep -Eq 'TEXTREL|Shared library: \[libgst' "$reports/$name-dynamic.txt"; then
    echo 'ERROR: unexpected GStreamer or TEXTREL dependency' >&2; exit 13;
  fi
  python3 - "$reports/$name-versions.txt" <<'PY'
import re,sys
v=[tuple(map(int,x.split('.'))) for x in re.findall(r'Name: GLIBC_([0-9.]+)',open(sys.argv[1]).read())]
assert all(x<=(2,41) for x in v),v
PY
done
cat > "$reports/consumer.c" <<'C'
#include <wayland-client.h>
#include <wayland-server.h>
#include <wayland-cursor.h>
#include <wayland-egl.h>
void *fire4nix_wpe_wayland_probe(void) {
  struct wl_display *client=wl_display_connect(NULL);
  struct wl_display *server=wl_display_create();
  struct wl_cursor_theme *cursor=wl_cursor_theme_load(NULL, 16, NULL);
  struct wl_egl_window *eglwin=wl_egl_window_create(NULL, 64, 48);
  return client ? (void *)client : server ? (void *)server :
         cursor ? (void *)cursor : (void *)eglwin;
}
C
"$cc" -O2 -mcpu=cortex-a35 -fPIC -shared -Wl,-z,defs \
  -I"$stage/usr/include" "$reports/consumer.c" -L"$stage/usr/lib" \
  -Wl,-rpath-link,"$stage/usr/lib" -Wl,--no-as-needed \
  -lwayland-client -lwayland-server -lwayland-cursor -lwayland-egl \
  -o "$reports/libfire4nix-wayland-consumer-aarch64.so"
readelf -h "$reports/libfire4nix-wayland-consumer-aarch64.so" > "$reports/consumer-header.txt"
readelf -d "$reports/libfire4nix-wayland-consumer-aarch64.so" > "$reports/consumer-dynamic.txt"
readelf -V "$reports/libfire4nix-wayland-consumer-aarch64.so" > "$reports/consumer-versions.txt"
grep -Eq 'Machine:.*AArch64' "$reports/consumer-header.txt"
for name in client server cursor egl; do
  grep -Fq "Shared library: [libwayland-$name.so." "$reports/consumer-dynamic.txt" || {
    echo "ERROR: Wayland test consumer missing wayland-$name DT_NEEDED" >&2; exit 14;
  }
done
{
  echo 'WAYLAND_TARGET_BUILD=PASS_REAL_ROCKNIX_AARCH64'
  echo 'WAYLAND_VERSION=1.23.1'
  echo 'WAYLAND_SOURCE=UPSTREAM_RELEASE_SHA256_VERIFIED'
  echo 'WAYLAND_HOST_SCANNER=PASS_SEPARATE_NATIVE_GENERATOR'
  echo 'WAYLAND_CLIENT_SERVER_CURSOR_EGL=PASS_TARGET_ELF64_GLIBC_2_41'
  echo 'WAYLAND_LINK_CONSUMER=PASS_FOUR_REAL_AARCH64_SONAMES'
  echo 'GSTREAMER=NOT_LINKED'
  echo 'WPE_WEBKIT_BUILT=no'
  echo 'TARGET_EXECUTED=no'
  echo 'R36H_INSTALLABLE=no'
} | tee "$reports/acceptance.txt"
cat "$reports/acceptance.txt" >> "$GITHUB_STEP_SUMMARY"
