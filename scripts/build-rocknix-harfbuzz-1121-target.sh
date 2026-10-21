#!/usr/bin/env bash
# Real HarfBuzz 11.2.1 ARM64 build addressing WPE 2.54.1 FindHarfBuzz.
# Only private GitHub runner stages; no R36H or host /usr modification.
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && "$(id -u)" != 0 && -n "${GITHUB_WORKSPACE:-}" ]] ||
  { echo 'ERROR: non-root Actions runner required' >&2; exit 4; }
root="$GITHUB_WORKSPACE"
sdk="$root/rocknix-source/build.ROCKNIX-RK3326.aarch64/toolchain"
cc="$sdk/bin/aarch64-rocknix-linux-gnu-gcc"
sysroot="$sdk/aarch64-rocknix-linux-gnu/sysroot"
font="$root/fontconfig-artifact/fontconfig-target/stage"
cairo="$root/cairo-artifact/cairo-target/stage"
work="$root/harfbuzz-target"
stage="$work/sysroot-overlay"
dest="$work/output"
report="$work/reports"
[[ ! -e "$work" && ! -L "$work" ]] || { echo 'ERROR: output exists' >&2; exit 4; }
mkdir -p "$work"/{source,reports,output}
[[ "$(git -C "$root/rocknix-source" rev-parse HEAD)" == 3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb ]] || exit 4
[[ "$("$cc" -dumpmachine)" == aarch64-rocknix-linux-gnu ]] || exit 4
readelf -h "$sysroot/usr/lib/libc.so.6" | grep -Eq 'Machine:.*AArch64'
recipe="$root/rocknix-source/packages/graphics/harfbuzz/package.mk"
hash=093714c8548a285094685f0bdc999e202d666b59eeb3df2ff921ab68b8336a49
grep -Fxq 'PKG_VERSION="11.2.1"' "$recipe"
grep -Fxq "PKG_SHA256=\"$hash\"" "$recipe"
grep -Fxq 'CAIRO_TARGET_BUILD=PASS_REAL_ROCKNIX_AARCH64' "$root/cairo-artifact/cairo-target/reports/acceptance.txt"
grep -Fxq 'FONTCONFIG_BUILD=PASS_REAL_ROCKNIX_AARCH64' "$root/fontconfig-artifact/fontconfig-target/reports/acceptance.txt"
for file in "$font/usr/lib/libglib-2.0.so.0" "$font/usr/lib/libfreetype.so.6" \
            "$font/usr/lib/libfontconfig.so.1" "$cairo/usr/lib/libcairo.so.2"; do
  [[ -s "$file" ]] && readelf -h "$file" | grep -Eq 'Machine:.*AArch64' || {
    echo "ERROR: missing genuine target shared library $file" >&2; exit 5;
  }
done
# Merge only expected private usr/include and usr/lib targets. Reject surprises.
python3 - "$font" "$cairo" "$stage" <<'PY'
from pathlib import Path
import hashlib, shutil, sys
sources=list(map(Path,sys.argv[1:3]))
dst=Path(sys.argv[3])
dst.mkdir(parents=True)
for source in sources:
    for sub in ('usr/include','usr/lib'):
        tree=source/sub
        if not tree.is_dir(): raise SystemExit(f'ERROR: absent real target path {tree}')
        for f in sorted(tree.rglob('*')):
            d=dst/f.relative_to(source)
            if f.is_symlink():
                target=f.readlink()
                if target.is_absolute() or '..' in target.parts:
                    raise SystemExit(f'ERROR: unsafe source symlink {f}')
                if d.is_symlink() and d.readlink()==target: continue
                if d.exists() or d.is_symlink(): raise SystemExit(f'ERROR: symlink collision {d}')
                d.parent.mkdir(parents=True,exist_ok=True); d.symlink_to(target)
            elif f.is_dir():
                if d.is_symlink() or (d.exists() and not d.is_dir()):
                    raise SystemExit(f'ERROR: directory collision {d}')
                d.mkdir(parents=True,exist_ok=True)
            elif f.is_file():
                if d.is_symlink() or (d.exists() and not d.is_file()):
                    raise SystemExit(f'ERROR: file collision {d}')
                if d.exists():
                    if hashlib.sha256(f.read_bytes()).digest()!=hashlib.sha256(d.read_bytes()).digest():
                        raise SystemExit(f'ERROR: different content collision {d}')
                else:
                    d.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(f,d)
            else: raise SystemExit(f'ERROR: unexpected target file type {f}')
print('HARFBUZZ_PREREQUISITE_STAGE=PASS_COLLISION_SAFE')
PY
export PKG_CONFIG_PATH=''
export PKG_CONFIG_LIBDIR="$stage/usr/lib/pkgconfig:$sysroot/usr/lib/pkgconfig:$sysroot/usr/share/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$stage"
for pc in cairo freetype2 glib-2.0 fontconfig pixman-1 libpng16; do
 pkg-config --exists "$pc" || { echo "ERROR: genuine target metadata $pc missing" >&2; exit 5; }
 echo "TARGET_PC_$pc=$(pkg-config --modversion "$pc")"
done | tee "$report/target-versions.txt"
archive="$work/harfbuzz-11.2.1.tar.xz"
curl --fail --location --silent --show-error --retry 2 \
 --proto '=https' --proto-redir '=https' --connect-timeout 15 --max-time 150 \
 'https://github.com/harfbuzz/harfbuzz/releases/download/11.2.1/harfbuzz-11.2.1.tar.xz' \
 --output "$archive"
echo "$hash  $archive" | sha256sum --check
tar -xJf "$archive" -C "$work/source" --strip-components=1
[[ -s "$work/source/meson.build" && -s "$work/source/meson_options.txt" ]] || {
 echo 'ERROR: HarfBuzz source tarball unexpectedly structured' >&2; exit 6;
}
echo 'HARFBUZZ_SOURCE=PASS_ROCKNIX_OFFICIAL_SHA256' > "$report/source.txt"
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
pkg_config_libdir = ['$stage/usr/lib/pkgconfig', '$sysroot/usr/lib/pkgconfig', '$sysroot/usr/share/pkgconfig']
[built-in options]
c_args = ['-mcpu=cortex-a35', '-I$stage/usr/include', '-I$stage/usr/include/glib-2.0', '-I$stage/usr/lib/glib-2.0/include', '-I$stage/usr/include/freetype2', '-I$stage/usr/include/cairo']
c_link_args = ['-L$stage/usr/lib', '-Wl,-rpath-link,$stage/usr/lib']
cpp_args = ['-mcpu=cortex-a35', '-I$stage/usr/include', '-I$stage/usr/include/glib-2.0', '-I$stage/usr/lib/glib-2.0/include', '-I$stage/usr/include/freetype2', '-I$stage/usr/include/cairo']
cpp_link_args = ['-L$stage/usr/lib', '-Wl,-rpath-link,$stage/usr/lib']
EOF
# Reproduce ROCKNIX target-enabled backends, with additional optional
# utilities/auto dependencies disabled to exclude host tool execution.
if ! meson setup "$work/build" "$work/source" --cross-file "$work/cross.ini" \
 --prefix=/usr --libdir=lib --buildtype=release --wrap-mode=nodownload \
 -Dbenchmark=disabled -Dcairo=enabled -Ddocs=disabled -Dfreetype=enabled \
 -Dglib=enabled -Dgobject=disabled -Dgraphite=disabled -Dgraphite2=disabled \
 -Dicu=disabled -Dtests=disabled -Dutilities=disabled -Dintrospection=disabled \
 -Dchafa=disabled -Dfontations=disabled \
 > "$report/configure.log" 2>&1; then
 echo 'HARFBUZZ_CONFIGURE=BLOCKED'
 grep -nE -B 4 -A 11 'ERROR:|Dependency .*not found|not found|Unknown options' "$report/configure.log" | head -n 150 || true
 tail -n 45 "$report/configure.log"
 exit 10
fi
if ! meson compile -C "$work/build" -j 2 > "$report/build.log" 2>&1; then
 echo 'HARFBUZZ_COMPILE=BLOCKED'
 grep -nE -B 4 -A 11 'FAILED:|fatal error:|error:|undefined reference' "$report/build.log" | head -n 150 || true
 tail -n 45 "$report/build.log"
 exit 11
fi
if ! DESTDIR="$dest" meson install -C "$work/build" --no-rebuild > "$report/install.log" 2>&1; then
 echo 'HARFBUZZ_INSTALL=BLOCKED'
 tail -n 75 "$report/install.log"
 exit 12
fi
lib="$dest/usr/lib/libharfbuzz.so.0"
[[ -s "$lib" && -s "$dest/usr/lib/pkgconfig/harfbuzz.pc" ]] || {
 echo 'ERROR: compiled target HarfBuzz SO or pc missing' >&2; exit 13;
}
readelf -h "$lib" > "$report/elf-header.txt"
readelf -d "$lib" > "$report/elf-dynamic.txt"
readelf -V "$lib" > "$report/elf-versions.txt"
grep -Eq 'Class:.*ELF64' "$report/elf-header.txt"
grep -Eq 'Machine:.*AArch64' "$report/elf-header.txt"
if grep -Eq 'TEXTREL|Shared library: \[libgst' "$report/elf-dynamic.txt";then
 echo 'ERROR: GStreamer or TEXTREL in HarfBuzz' >&2; exit 14
fi
python3 - "$report/elf-versions.txt" <<'PY'
import pathlib,re,sys
v=[tuple(map(int,x.split('.'))) for x in re.findall(r'Name: GLIBC_([0-9]+\.[0-9]+)',pathlib.Path(sys.argv[1]).read_text())]
assert all(x<=(2,41) for x in v),v
print('HARFBUZZ_GLIBC=PASS_MAX_2_41')
PY
export PKG_CONFIG_LIBDIR="$dest/usr/lib/pkgconfig:$stage/usr/lib/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$dest"
pkg-config --exists 'harfbuzz >= 11.2.1'
pkg-config --modversion harfbuzz > "$report/harfbuzz-pc-version.txt"
cat > "$work/hb-consumer.cc" <<'C'
#include <hb.h>
#include <hb-ft.h>
#include <hb-glib.h>
int fire4nix_text_shape_probe(void) {
  hb_buffer_t* buffer=hb_buffer_create();
  hb_buffer_add_utf8(buffer, "Fire4Nix R36H", -1, 0, -1);
  hb_buffer_guess_segment_properties(buffer);
  hb_font_t* font=hb_font_get_empty();
  hb_shape(font,buffer,nullptr,0);
  unsigned n=hb_buffer_get_length(buffer);
  hb_buffer_destroy(buffer);
  return n > 0 ? 0 : 1;
}
C
"$sdk/bin/aarch64-rocknix-linux-gnu-g++" -O2 -mcpu=cortex-a35 -fPIC \
 -shared -Wl,-z,defs -I"$dest/usr/include/harfbuzz" \
 -I"$stage/usr/include/glib-2.0" -I"$stage/usr/lib/glib-2.0/include" \
 -I"$stage/usr/include/freetype2" \
 "$work/hb-consumer.cc" -L"$dest/usr/lib" -L"$stage/usr/lib" \
 -Wl,-rpath-link,"$dest/usr/lib" -Wl,-rpath-link,"$stage/usr/lib" \
 -lharfbuzz -o "$work/libfire4nix-harfbuzz-consumer.so"
readelf -h "$work/libfire4nix-harfbuzz-consumer.so" > "$report/consumer-header.txt"
readelf -d "$work/libfire4nix-harfbuzz-consumer.so" > "$report/consumer-dynamic.txt"
grep -Eq 'Machine:.*AArch64' "$report/consumer-header.txt"
grep -Fq 'Shared library: [libharfbuzz.so.0]' "$report/consumer-dynamic.txt"
{
 echo 'HARFBUZZ_VERSION=11.2.1_ROCKNIX'
 echo 'HARFBUZZ_TARGET_BUILD=PASS_REAL_ROCKNIX_AARCH64'
 echo 'HARFBUZZ_CAIRO_FREETYPE_GLIB_CONFIGURED=YES'
 echo 'HARFBUZZ_TARGET_CONSUMER_LINK=PASS_ELF64_AARCH64'
 echo 'HARFBUZZ_TARGET_GLIBC_MAX=2.41'
 echo 'TARGET_EXECUTED=no'
 echo 'WPE_WEBKIT_BUILT=no'
 echo 'R36H_INSTALLABLE=no'
} | tee "$report/acceptance.txt"
