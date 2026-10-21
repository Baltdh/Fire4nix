#!/usr/bin/env bash
# Genuine ROCKNIX 20260801 libxml2 2.14.4 ARM64 target build, private stage only.
set -euo pipefail
[[ ${GITHUB_ACTIONS:-} == true && $(id -u) != 0 && -n ${GITHUB_WORKSPACE:-} ]] || { echo 'ERROR: non-root GitHub CI only'; exit 4; }
root="$GITHUB_WORKSPACE"
sdk="$root/rocknix-source/build.ROCKNIX-RK3326.aarch64/toolchain"
recipe="$root/rocknix-source/packages/textproc/libxml2/package.mk"
work="$root/libxml2-target"
[[ ! -e "$work" && ! -L "$work" ]] || { echo 'ERROR: refusing existing build directory'; exit 4; }
mkdir -p "$work"/{source,stage,reports}
[[ $(git -C "$root/rocknix-source" rev-parse HEAD) == 3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb ]]
hash=8e20c2ef2fc7965d7851e3ab3a756c3fc8b449ba47526269a9b4d7f0480550db
grep -Fxq 'PKG_VERSION="2.14.4"' "$recipe"
grep -Fxq "PKG_SHA256=\"$hash\"" "$recipe"
cc="$sdk/bin/aarch64-rocknix-linux-gnu-gcc"
[[ $("$cc" -dumpmachine) == aarch64-rocknix-linux-gnu ]]
echo 'LIBXML2_SOURCE=DOWNLOAD_ORIGINAL_ROCKNIX'
curl -fL --silent --show-error --retry 2 --connect-timeout 15 --max-time 150 \
 --proto '=https' --proto-redir '=https' \
 https://gitlab.gnome.org/GNOME/libxml2/-/archive/v2.14.4/libxml2-v2.14.4.tar.bz2 \
 -o "$work/source.tar.bz2"
echo "$hash  $work/source.tar.bz2" | sha256sum -c -
tar -xjf "$work/source.tar.bz2" --strip-components=1 -C "$work/source"
test -f "$work/source/CMakeLists.txt"
echo 'LIBXML2_CMAKE_CONFIGURE=START'
if ! cmake -S "$work/source" -B "$work/build" -G Ninja \
 -DCMAKE_TOOLCHAIN_FILE="$sdk/fire4nix-toolchain.cmake" \
 -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_INSTALL_LIBDIR=lib \
 -DBUILD_SHARED_LIBS=ON \
 -DLIBXML2_WITH_ICONV=OFF -DLIBXML2_WITH_ICU=OFF \
 -DLIBXML2_WITH_LZMA=OFF -DLIBXML2_WITH_TESTS=OFF \
 -DLIBXML2_WITH_THREADS=ON -DLIBXML2_WITH_ZLIB=OFF \
 -DLIBXML2_WITH_PYTHON=OFF \
 > "$work/reports/configure.log" 2>&1; then
 echo 'LIBXML2_CMAKE_CONFIGURE=BLOCKED'; tail -n 110 "$work/reports/configure.log"; exit 10
fi
echo 'LIBXML2_CMAKE_CONFIGURE=PASS'
if ! cmake --build "$work/build" --parallel 2 > "$work/reports/build.log" 2>&1; then
 echo 'LIBXML2_TARGET_BUILD=BLOCKED'; tail -n 110 "$work/reports/build.log"; exit 11
fi
echo 'LIBXML2_TARGET_BUILD=PASS'
if ! DESTDIR="$work/stage" cmake --install "$work/build" > "$work/reports/install.log" 2>&1; then
 echo 'LIBXML2_INSTALL=BLOCKED'; tail -n 95 "$work/reports/install.log"; exit 12
fi
# Resolve versioned ELF via the provided SONAME link; no target code execution.
lib="$work/stage/usr/lib/libxml2.so.16"
if ! test -s "$lib"; then
 lib=$(find "$work/stage/usr/lib" -maxdepth 1 -type f -name 'libxml2.so*' -print -quit)
fi
test -n "$lib" && test -s "$lib"
readelf -h "$lib" > "$work/reports/elf-header.txt"
readelf -d "$lib" > "$work/reports/elf-dynamic.txt"
readelf -V "$lib" > "$work/reports/elf-versions.txt"
readelf -Ws "$lib" > "$work/reports/elf-symbols.txt"
grep -Eq 'Class:.*ELF64' "$work/reports/elf-header.txt"
grep -Eq 'Machine:.*AArch64' "$work/reports/elf-header.txt"
grep -Eq 'GLOBAL.*DEFAULT.*xmlReadMemory' "$work/reports/elf-symbols.txt"
if grep -Eq 'TEXTREL|Shared library: \[libgst' "$work/reports/elf-dynamic.txt"; then
 echo 'ERROR: forbidden dependency/relocation'; exit 13
fi
python3 - "$work/reports/elf-versions.txt" <<'PY'
import re,sys
v=[tuple(map(int,x.split('.'))) for x in re.findall(r'Name: GLIBC_([0-9.]+)',open(sys.argv[1]).read())]
assert all(x <= (2,41) for x in v),v
print('LIBXML2_ELF_GLIBC=PASS_MAX_2_41')
PY
export PKG_CONFIG_LIBDIR="$work/stage/usr/lib/pkgconfig" PKG_CONFIG_PATH='' PKG_CONFIG_SYSROOT_DIR="$work/stage"
echo 'LIBXML2_PKGCONFIG_INSPECT=START'
find "$work/stage/usr" -type f -name 'libxml-2.0.pc' -print
version=$(pkg-config --modversion libxml-2.0 2>&1) || { echo "ERROR: target libxml-2.0.pc missing: $version"; exit 14; }
echo "LIBXML2_PKGCONFIG_VERSION=$version"
[[ "$version" == 2.14.4 ]] || { echo "ERROR: unexpected target pkg-config version $version"; exit 14; }
cat > "$work/consumer.c" <<'C'
#include <libxml/parser.h>
int fire4nix_libxml2_probe(void) {
 const char *html="<html><body>R36H offline</body></html>";
 xmlDocPtr d=xmlReadMemory(html,-1,"offline.html",NULL,XML_PARSE_NONET|XML_PARSE_RECOVER|XML_PARSE_NOERROR);
 if (!d) return 0;
 xmlFreeDoc(d);
 return 1;
}
C
"$cc" -O2 -mcpu=cortex-a35 -fPIC -shared -Wl,-z,defs \
 -I"$work/stage/usr/include/libxml2" "$work/consumer.c" \
 -L"$work/stage/usr/lib" -Wl,-rpath-link,"$work/stage/usr/lib" \
 -lxml2 -o "$work/libfire4nix-xml-probe.so"
readelf -h "$work/libfire4nix-xml-probe.so" | grep -Eq 'Machine:.*AArch64'
readelf -d "$work/libfire4nix-xml-probe.so" | tee "$work/reports/consumer-dynamic.txt" | grep -Fq 'Shared library: [libxml2.so.16]'
{
 echo 'LIBXML2_BUILD=PASS_REAL_ROCKNIX_AARCH64'
 echo 'LIBXML2_VERSION=2.14.4'
 echo 'XML_PARSE_NONET=COMPILED_NOT_EXECUTED'
 echo 'ROCKNIX_GLIBC_MAX=2.41'
 echo 'WEBKIT_BUILT=no'
 echo 'R36H_INSTALLABLE=no'
} | tee "$work/reports/result.txt"
cat "$work/reports/result.txt" >> "$GITHUB_STEP_SUMMARY"
