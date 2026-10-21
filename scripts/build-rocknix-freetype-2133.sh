#!/usr/bin/env bash
# ROCKNIX 20260801 FreeType 2.13.3 target build using genuine AArch64 libpng/zlib.
# Separate build artifact only; never install into an R36H or Ubuntu /usr.
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && "$(id -u)" != 0 && -n "${GITHUB_WORKSPACE:-}" ]] ||
  { echo 'ERROR: non-root Actions runner only' >&2; exit 4; }
root="$GITHUB_WORKSPACE"
sdk="$root/rocknix-source/build.ROCKNIX-RK3326.aarch64/toolchain"
cc="$sdk/bin/aarch64-rocknix-linux-gnu-gcc"
stage="$root/eight-artifact/eight-deps/stage"
work="$root/freetype-target"
[[ ! -e "$work" && ! -L "$work" ]] || { echo 'ERROR: workdir already exists' >&2; exit 4; }
mkdir -p "$work"/{source,build,stage,reports}
[[ "$(git -C "$root/rocknix-source" rev-parse HEAD)" == 3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb ]] || exit 4
[[ "$("$cc" -dumpmachine)" == 'aarch64-rocknix-linux-gnu' ]] || exit 4
grep -Fxq 'PKG_VERSION="2.13.3"' "$root/rocknix-source/packages/print/freetype/package.mk"
expected=0550350666d427c74daeb85d5ac7bb353acba5f76956395995311a9c6f063289
grep -Fxq "PKG_SHA256=\"$expected\"" "$root/rocknix-source/packages/print/freetype/package.mk"
for f in "$stage/usr/lib/libz.so" "$stage/usr/lib/libpng16.so" \
 "$stage/usr/lib/pkgconfig/libpng16.pc" "$stage/usr/include/png.h"; do
 [[ -s "$f" ]] || { echo "ERROR: target input missing: $f" >&2; exit 5; }
done
archive="$work/freetype-2.13.3.tar.xz"
success=0
for url in \
  'https://download.savannah.gnu.org/releases/freetype/freetype-2.13.3.tar.xz' \
  'https://downloads.sourceforge.net/project/freetype/freetype2/2.13.3/freetype-2.13.3.tar.xz'; do
  rm -f "$archive"
  if curl --fail --location --silent --show-error --retry 1 \
      --proto '=https' --proto-redir '=https' \
      --connect-timeout 12 --max-time 100 "$url" --output "$archive" &&
     echo "$expected  $archive" | sha256sum --check; then
    printf 'FREETYPE_SOURCE_VERIFIED_URL=%s\n' "$url" > "$work/reports/source.txt"
    success=1
    break
  fi
done
[[ "$success" -eq 1 ]] || { echo 'ERROR: no original-hash-matching freetype release' >&2; exit 5; }
tar -xJf "$archive" -C "$work/source" --strip-components=1
[[ -s "$work/source/configure" && -s "$work/source/include/ft2build.h" ]] || {
  echo 'ERROR: freetype source archive incomplete' >&2; exit 5;
}
echo 'FREETYPE_ARCHIVE_SHA256=PASS_PINNED_ROCKNIX_20260801' >> "$work/reports/source.txt"
export PKG_CONFIG_PATH=''
export PKG_CONFIG_LIBDIR="$stage/usr/lib/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$stage"
export CPPFLAGS="-I$stage/usr/include"
export CFLAGS='-O2 -mcpu=cortex-a35 -fPIC'
export LDFLAGS="-L$stage/usr/lib -Wl,-rpath-link,$stage/usr/lib"
export LIBPNG_CFLAGS="-I$stage/usr/include"
export LIBPNG_LIBS="-L$stage/usr/lib -lpng16 -lz"
export ZLIB_CFLAGS="-I$stage/usr/include"
export ZLIB_LIBS="-L$stage/usr/lib -lz"
cd "$work/build"
if ! CC="$cc" \
  AR="$sdk/bin/aarch64-rocknix-linux-gnu-ar" \
  RANLIB="$sdk/bin/aarch64-rocknix-linux-gnu-ranlib" \
  "$work/source/configure" \
  --host=aarch64-rocknix-linux-gnu --build="$(gcc -dumpmachine)" \
  --prefix=/usr --libdir=/usr/lib \
  --enable-shared --enable-static \
  --with-zlib=yes --with-png=yes \
  --without-bzip2 --without-brotli --without-harfbuzz \
  > "$work/reports/configure.log" 2>&1; then
    tail -n 95 "$work/reports/configure.log"
    exit 9
fi
if ! make -j2 > "$work/reports/build.log" 2>&1; then
  tail -n 100 "$work/reports/build.log"
  exit 10
fi
if ! make DESTDIR="$work/stage" install > "$work/reports/install.log" 2>&1; then
  tail -n 80 "$work/reports/install.log"
  exit 11
fi
so="$work/stage/usr/lib/libfreetype.so.6"
[[ -s "$so" ]] || { echo 'ERROR: shared target FreeType soname unavailable' >&2; exit 12; }
readelf -h "$so" > "$work/reports/elf-header.txt"
readelf -d "$so" > "$work/reports/elf-dynamic.txt"
readelf -V "$so" > "$work/reports/elf-versions.txt"
grep -Eq 'Class:.*ELF64' "$work/reports/elf-header.txt"
grep -Eq 'Machine:.*AArch64' "$work/reports/elf-header.txt"
grep -Fq 'Shared library: [libz.so.1]' "$work/reports/elf-dynamic.txt" ||
  { echo 'ERROR: FreeType not linked to target zlib'; exit 12; }
grep -Fq 'Shared library: [libpng16.so.16]' "$work/reports/elf-dynamic.txt" ||
  { echo 'ERROR: FreeType not linked to target PNG'; exit 12; }
if grep -Eq 'TEXTREL|Shared library: \[libgst' "$work/reports/elf-dynamic.txt"; then
 echo 'ERROR: invalid media dependency or textrel' >&2; exit 12
fi
python3 - "$work/reports/elf-versions.txt" <<'PY'
import pathlib,re,sys
v=[tuple(map(int,x.split('.'))) for x in re.findall(r'Name: GLIBC_([0-9]+\.[0-9]+)',pathlib.Path(sys.argv[1]).read_text())]
assert all(x<=(2,41) for x in v),v
print('FREETYPE_GLIBC=PASS_MAX_2_41')
PY
[[ -s "$work/stage/usr/include/freetype2/ft2build.h" ]] || { echo 'ERROR: target freetype header absent'; exit 12; }
[[ -s "$work/stage/usr/lib/pkgconfig/freetype2.pc" ]] || { echo 'ERROR: target freetype2.pc absent'; exit 12; }
export PKG_CONFIG_LIBDIR="$work/stage/usr/lib/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$work/stage"
pkg-config --exists 'freetype2 >= 2.13.3'
pkg-config --modversion freetype2 > "$work/reports/freetype-pc-version.txt"
cat > "$work/build/freetype-consumer.c" <<'C'
#include <ft2build.h>
#include FT_FREETYPE_H
int fire4nix_font_probe(void) {
 FT_Library library=0;
 if (FT_Init_FreeType(&library)) return -1;
 return FT_Done_FreeType(library);
}
C
"$cc" -O2 -mcpu=cortex-a35 -fPIC -shared -Wl,-z,defs \
  -I"$work/stage/usr/include/freetype2" \
  "$work/build/freetype-consumer.c" -L"$work/stage/usr/lib" \
  -Wl,-rpath-link,"$stage/usr/lib" -Wl,-rpath-link,"$work/stage/usr/lib" \
  -lfreetype -o "$work/build/libfreetype-consumer-aarch64.so"
readelf -h "$work/build/libfreetype-consumer-aarch64.so" > "$work/reports/consumer-elf-header.txt"
readelf -d "$work/build/libfreetype-consumer-aarch64.so" > "$work/reports/consumer-dynamic.txt"
grep -Eq 'Machine:.*AArch64' "$work/reports/consumer-elf-header.txt"
grep -Fq 'Shared library: [libfreetype.so.6]' "$work/reports/consumer-dynamic.txt"
{
 echo 'FREETYPE_VERSION=2.13.3_ROCKNIX'
 echo 'FREETYPE_SOURCE=PASS_ORIGINAL_ROCKNIX_SHA256'
 echo 'FREETYPE_BUILD=PASS_REAL_ROCKNIX_AARCH64'
 echo 'FREETYPE_TARGET_NEEDED=libpng16.so.16,libz.so.1'
 echo 'FREETYPE_CONSUMER_LINK=PASS_ELF64_AARCH64'
 echo 'FREETYPE_TARGET_GLIBC_MAX=2.41'
 echo 'TARGET_EXECUTED=no'
 echo 'WEBKIT_BUILT=no'
 echo 'R36H_INSTALLABLE=no'
} | tee "$work/reports/result.txt"
