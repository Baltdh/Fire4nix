#!/usr/bin/env bash
# Genuine ROCKNIX Cairo 1.17.8 target ABI build; WPE/media-free variant:
# Xlib/XCB are deliberately omitted while target Wayland and Mesa are pending.
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && "$(id -u)" != 0 && -n "${GITHUB_WORKSPACE:-}" ]] || {
  echo 'ERROR: non-root GitHub runner only. No R36H device or firmware access.' >&2; exit 4;
}
root="$GITHUB_WORKSPACE"
sdk="$root/rocknix-source/build.ROCKNIX-RK3326.aarch64/toolchain"
cc="$sdk/bin/aarch64-rocknix-linux-gnu-gcc"
sysroot="$sdk/aarch64-rocknix-linux-gnu/sysroot"
input="$root/fontconfig-artifact/fontconfig-target/stage"
reports="$root/cairo-target/reports"
source="$root/cairo-target/source"
build="$root/cairo-target/build"
stage="$root/cairo-target/stage"
[[ ! -e "$root/cairo-target" && ! -L "$root/cairo-target" ]] || {
  echo 'ERROR: output directory already exists' >&2; exit 4;
}
mkdir -p "$reports" "$source" "$stage"
[[ "$(git -C "$root/rocknix-source" rev-parse HEAD)" == 3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb ]] || exit 4
[[ "$("$cc" -dumpmachine)" == aarch64-rocknix-linux-gnu ]] || exit 4
[[ -s "$sdk/fire4nix-toolchain.cmake" && -s "$sysroot/usr/lib/libc.so.6" ]] || exit 4
readelf -h "$sysroot/usr/lib/libc.so.6" | grep -Eq 'Machine:.*AArch64'
recipe="$root/rocknix-source/projects/ROCKNIX/packages/graphics/cairo/package.mk"
generic="$root/rocknix-source/packages/graphics/cairo/package.mk"
expected=5b10c8892d1b58d70d3f0ba5b47863a061262fa56b9dc7944161f8c8b783bc64
grep -Fxq 'PKG_VERSION="1.17.8"' "$recipe"
grep -Fxq "PKG_SHA256=\"$expected\"" "$recipe"
grep -Fxq 'PKG_VERSION="1.18.4"' "$generic"
input_report="$root/fontconfig-artifact/fontconfig-target/reports/acceptance.txt"
[[ -s "$input_report" ]] && grep -Fxq 'FONTCONFIG_BUILD=PASS_REAL_ROCKNIX_AARCH64' "$input_report" || {
  echo 'ERROR: do not consume an unverified/pending Fontconfig artifact' >&2; exit 5;
}
for so in libfontconfig.so.1 libfreetype.so.6 libpixman-1.so.0 libpng16.so.16 libglib-2.0.so.0; do
  f="$input/usr/lib/$so"
  [[ -s "$f" ]] || { echo "ERROR: missing genuine target $so" >&2; exit 5; }
  readelf -h "$f" | grep -Eq 'Machine:.*AArch64' || {
    echo "ERROR: non-AArch64 target dependency $f" >&2; exit 5;
  }
done
for pc in fontconfig freetype2 pixman-1 libpng16 glib-2.0 zlib; do
  [[ -s "$input/usr/lib/pkgconfig/$pc.pc" ]] || { echo "ERROR: missing $pc target pc" >&2; exit 5; }
done
export PKG_CONFIG_PATH=''
export PKG_CONFIG_LIBDIR="$input/usr/lib/pkgconfig:$sysroot/usr/lib/pkgconfig:$sysroot/usr/share/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$input"
for pc in fontconfig freetype2 pixman-1 libpng16 glib-2.0 zlib; do
  pkg-config --exists "$pc" || { echo "ERROR: target pkg-config cannot find $pc" >&2; exit 5; }
  echo "$pc=$(pkg-config --modversion "$pc")"
done | tee "$reports/real-target-prerequisites.txt"
archive="$root/cairo-target/cairo-1.17.8.tar.xz"
curl --fail --location --silent --show-error --retry 2 \
  --proto '=https' --proto-redir '=https' --connect-timeout 15 --max-time 150 \
  'https://cairographics.org/snapshots/cairo-1.17.8.tar.xz' --output "$archive"
echo "$expected  $archive" | sha256sum --check
tar -xJf "$archive" -C "$source" --strip-components=1
[[ -s "$source/meson.build" && -s "$source/meson_options.txt" || -s "$source/meson.options" ]] || {
  echo 'ERROR: Cairo upstream Meson files missing' >&2; exit 6;
}
{
 echo 'CAIRO_VERSION=1.17.8_ROCKNIX_PROJECT_OVERRIDE'
 echo "CAIRO_SOURCE_SHA256=$expected"
 echo 'CAIRO_ORIGINAL_TARBALL_SHA256=PASS'
} > "$reports/provenance.txt"
# The official ROCKNIX recipe changes this exact Meson cross-run test. Mirror
# only that specific change in the private extracted source, never the archive.
python3 - "$source/meson.build" "$reports" <<'PY'
from pathlib import Path
import sys
file=Path(sys.argv[1])
reports=Path(sys.argv[2])
text=file.read_text()
old="'ipc_rmid_deferred_release', 'auto'"
new="'ipc_rmid_deferred_release', 'true'"
if text.count(old)!=1:
    raise SystemExit("ERROR: expected one ROCKNIX Cairo IPC probe replacement")
file.write_text(text.replace(old,new,1))
(reports/'rocknix-ipc-target-workaround.txt').write_text(
    f"RECIPE_PATCH={old} -> {new}\nORIGINAL_ARCHIVE_UNCHANGED=yes\n")
PY
cat > "$root/cairo-target/cross.ini" <<EOF
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
pkg_config_libdir = ['$input/usr/lib/pkgconfig', '$sysroot/usr/lib/pkgconfig', '$sysroot/usr/share/pkgconfig']
[built-in options]
c_args = ['-mcpu=cortex-a35', '-I$input/usr/include', '-I$input/usr/include/freetype2', '-I$input/usr/include/pixman-1']
c_link_args = ['-L$input/usr/lib', '-Wl,-rpath-link,$input/usr/lib']
cpp_args = ['-mcpu=cortex-a35', '-I$input/usr/include']
cpp_link_args = ['-L$input/usr/lib', '-Wl,-rpath-link,$input/usr/lib']
EOF
# Compatible with the ROCKNIX Cairo 1.17.8 recipe. Disable Xlib/XCB while
# testing the portable image/font backends: the system's Wayland profile also
# enables X11 libraries and those *have not yet been built in this stage*.
if ! meson setup "$build" "$source" --cross-file "$root/cairo-target/cross.ini" \
 --prefix=/usr --libdir=lib --buildtype=release --wrap-mode=nodownload \
 -Ddwrite=disabled -Dfontconfig=enabled -Dfreetype=enabled -Dpng=enabled \
 -Dquartz=disabled -Dtee=disabled -Dxcb=disabled -Dxlib=disabled \
 -Dxlib-xcb=disabled -Dzlib=enabled -Dtests=disabled -Dxml=disabled \
 -Dgtk2-utils=disabled -Dglib=enabled -Dspectre=disabled \
 -Dsymbol-lookup=disabled -Dgtk_doc=false \
 > "$reports/configure.log" 2>&1; then
    echo 'CAIRO_CONFIGURE=BLOCKED'
    tail -n 105 "$reports/configure.log"
    exit 10
fi
if ! meson compile -C "$build" -j 2 > "$reports/build.log" 2>&1; then
    echo 'CAIRO_BUILD=BLOCKED'
    grep -nE -B 5 -A 12 'FAILED:|error:|undefined reference|fatal error:|not found' "$reports/build.log" | head -n 180 || true
    tail -n 45 "$reports/build.log"
    exit 11
fi
if ! DESTDIR="$stage" meson install -C "$build" --no-rebuild > "$reports/install.log" 2>&1; then
    echo 'CAIRO_INSTALL=BLOCKED'
    tail -n 100 "$reports/install.log"
    exit 12
fi
[[ -s "$stage/usr/lib/libcairo.so.2" && -s "$stage/usr/lib/pkgconfig/cairo.pc" ]] || {
  echo 'ERROR: target libcairo.so.2 or cairo.pc not staged' >&2; exit 13;
}
readelf -h "$stage/usr/lib/libcairo.so.2" > "$reports/cairo-elf-header.txt"
readelf -d "$stage/usr/lib/libcairo.so.2" > "$reports/cairo-elf-dynamic.txt"
readelf -V "$stage/usr/lib/libcairo.so.2" > "$reports/cairo-elf-versions.txt"
grep -Eq 'Class:.*ELF64' "$reports/cairo-elf-header.txt"
grep -Eq 'Machine:.*AArch64' "$reports/cairo-elf-header.txt"
grep -Fq 'Shared library: [libpixman-1.so.0]' "$reports/cairo-elf-dynamic.txt"
grep -Fq 'Shared library: [libfontconfig.so.1]' "$reports/cairo-elf-dynamic.txt"
grep -Fq 'Shared library: [libfreetype.so.6]' "$reports/cairo-elf-dynamic.txt"
if grep -Eq 'TEXTREL|Shared library: \[libgst' "$reports/cairo-elf-dynamic.txt"; then
  echo 'ERROR: invalid Cairo relocation/media dependency' >&2; exit 14
fi
python3 - "$reports/cairo-elf-versions.txt" <<'PY'
from pathlib import Path
import re,sys
s=Path(sys.argv[1]).read_text()
v=[tuple(map(int,x.split('.'))) for x in re.findall(r'Name: GLIBC_([0-9]+\.[0-9]+)',s)]
assert all(x<=(2,41) for x in v),v
print('CAIRO_GLIBC=PASS_MAX_2_41')
PY
export PKG_CONFIG_LIBDIR="$stage/usr/lib/pkgconfig:$input/usr/lib/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$stage"
pkg-config --exists 'cairo >= 1.17.8'
pkg-config --modversion cairo > "$reports/cairo-pc-version.txt"
cat > "$root/cairo-target/cairo-consumer.c" <<'C'
#include <cairo.h>
#include <cairo-ft.h>
int fire4nix_cairo_consumer(void) {
  cairo_surface_t *surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 64, 64);
  cairo_t *cr = cairo_create(surface);
  cairo_set_source_rgb(cr, 0.2, 0.3, 0.4);
  cairo_paint(cr);
  cairo_status_t status = cairo_status(cr);
  cairo_destroy(cr);
  cairo_surface_destroy(surface);
  return status;
}
C
"$cc" -O2 -mcpu=cortex-a35 -fPIC -shared -Wl,-z,defs \
  -I"$stage/usr/include/cairo" -I"$input/usr/include/freetype2" \
  "$root/cairo-target/cairo-consumer.c" -L"$stage/usr/lib" \
  -Wl,-rpath-link,"$input/usr/lib" -Wl,-rpath-link,"$stage/usr/lib" \
  -lcairo -o "$root/cairo-target/libfire4nix-cairo-consumer.so"
readelf -h "$root/cairo-target/libfire4nix-cairo-consumer.so" > "$reports/consumer-header.txt"
readelf -d "$root/cairo-target/libfire4nix-cairo-consumer.so" > "$reports/consumer-dynamic.txt"
grep -Eq 'Machine:.*AArch64' "$reports/consumer-header.txt"
grep -Fq 'Shared library: [libcairo.so.2]' "$reports/consumer-dynamic.txt"
{
 echo 'CAIRO_TARGET_BUILD=PASS_REAL_ROCKNIX_AARCH64'
 echo 'CAIRO_VERSION=1.17.8_ROCKNIX_PROJECT_EFFECTIVE'
 echo 'CAIRO_FONT_BACKENDS=FONTCONFIG_FREETYPE_ENABLED'
 echo 'CAIRO_PIXMAN=REAL_TARGET_0.46.2'
 echo 'CAIRO_WPE_MINIMAL_X11_PROFILE=DISABLED_XLIB_XCB_UNTIL_TARGET_LIBS'
 echo 'CAIRO_SOURCE_HASH=ORIGINAL_ROCKNIX_SHA256_VERIFIED'
 echo 'CAIRO_TARGET_CONSUMER_LINK=PASS_ELF64_AARCH64'
 echo 'TARGET_GLIBC_MAX=2.41'
 echo 'TARGET_EXECUTED=no'
 echo 'WPE_WEBKIT_BUILT=no'
 echo 'R36H_INSTALLABLE=no'
} | tee "$reports/acceptance.txt"
