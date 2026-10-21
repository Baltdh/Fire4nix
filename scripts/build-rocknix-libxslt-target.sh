#!/usr/bin/env bash
# Genuine ROCKNIX RK3326 libxslt 1.1.43 using already-built target libxml2 2.14.4.
set -euo pipefail
[[ ${GITHUB_ACTIONS:-} == true && $(id -u) != 0 && -n ${GITHUB_WORKSPACE:-} ]] || { echo 'ERROR: non-root CI only'; exit 4; }
root="$GITHUB_WORKSPACE"
sdk="$root/rocknix-source/build.ROCKNIX-RK3326.aarch64/toolchain"
recipe="$root/rocknix-source/packages/textproc/libxslt/package.mk"
xml="$root/xml-artifact/libxml2-target/stage"
work="$root/libxslt-target"
[[ ! -e "$work" && ! -L "$work" ]] || { echo 'ERROR: refusing overwrite'; exit 4; }
mkdir -p "$work"/{source,stage,reports}
[[ $(git -C "$root/rocknix-source" rev-parse HEAD) == 3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb ]]
hash=5a3d6b383ca5afc235b171118e90f5ff6aa27e9fea3303065231a6d403f0183a
grep -Fxq 'PKG_VERSION="1.1.43"' "$recipe"
grep -Fxq "PKG_SHA256=\"$hash\"" "$recipe"
cc="$sdk/bin/aarch64-rocknix-linux-gnu-gcc"
[[ $("$cc" -dumpmachine) == aarch64-rocknix-linux-gnu ]]
for f in "$xml/usr/lib/libxml2.so.16" "$xml/usr/include/libxml2/libxml/parser.h"; do
 test -s "$f" || { echo "ERROR: missing target libxml2 artifact $f"; exit 4; }
done
echo 'LIBXSLT_SOURCE=DOWNLOAD_OFFICIAL_RECIPE'
curl --proto '=https' --proto-redir '=https' -fLsS --retry 2 --connect-timeout 15 --max-time 160 \
 https://download.gnome.org/sources/libxslt/1.1/libxslt-1.1.43.tar.xz \
 -o "$work/source.tar.xz"
echo "$hash  $work/source.tar.xz" | sha256sum -c -
tar -xJf "$work/source.tar.xz" --strip-components=1 -C "$work/source"
test -f "$work/source/CMakeLists.txt"
export PKG_CONFIG_LIBDIR="$xml/usr/lib/pkgconfig" PKG_CONFIG_PATH='' PKG_CONFIG_SYSROOT_DIR="$xml"
echo 'LIBXSLT_CMAKE_CONFIGURE=START'
if ! cmake -S "$work/source" -B "$work/build" -G Ninja \
 -DCMAKE_TOOLCHAIN_FILE="$sdk/fire4nix-toolchain.cmake" \
 -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_INSTALL_LIBDIR=lib \
 -DCMAKE_PREFIX_PATH="$xml/usr" \
 -DLibXml2_DIR="$xml/usr/lib/cmake/libxml2-2.14.4" \
 -DCMAKE_SHARED_LINKER_FLAGS="-L$xml/usr/lib -Wl,-rpath-link,$xml/usr/lib" \
 -DLIBXML2_INCLUDE_DIR="$xml/usr/include/libxml2" \
 -DLIBXML2_LIBRARY="$xml/usr/lib/libxml2.so.16" \
 -DBUILD_SHARED_LIBS=ON \
 -DLIBXSLT_WITH_DEBUGGER=OFF -DLIBXSLT_WITH_CRYPTO=OFF \
 -DLIBXSLT_WITH_MODULES=OFF -DLIBXSLT_WITH_PROFILER=ON \
 -DLIBXSLT_WITH_PYTHON=OFF -DLIBXSLT_WITH_TESTS=OFF \
 -DLIBXSLT_WITH_THREADS=ON -DLIBXSLT_WITH_XSLT_DEBUG=OFF \
 > "$work/reports/configure.log" 2>&1; then
 echo 'LIBXSLT_CMAKE_CONFIGURE=BLOCKED'; tail -n 105 "$work/reports/configure.log"; exit 10
fi
echo 'LIBXSLT_CMAKE_CONFIGURE=PASS'
if ! cmake --build "$work/build" --parallel 2 > "$work/reports/build.log" 2>&1; then
 echo 'LIBXSLT_TARGET_BUILD=BLOCKED'; tail -n 100 "$work/reports/build.log"; exit 11
fi
echo 'LIBXSLT_TARGET_BUILD=PASS'
if ! DESTDIR="$work/stage" cmake --install "$work/build" > "$work/reports/install.log" 2>&1; then
 echo 'LIBXSLT_INSTALL=BLOCKED'; tail -n 90 "$work/reports/install.log"; exit 12
fi
lib=$(find "$work/stage/usr/lib" -maxdepth 1 -type f -name 'libxslt.so.*' -print -quit)
test -n "$lib" && test -s "$lib"
readelf -h "$lib" > "$work/reports/elf-header.txt"
readelf -d "$lib" > "$work/reports/elf-dynamic.txt"
readelf -V "$lib" > "$work/reports/elf-versions.txt"
grep -Eq 'Class:.*ELF64' "$work/reports/elf-header.txt"
grep -Eq 'Machine:.*AArch64' "$work/reports/elf-header.txt"
grep -Fq 'Shared library: [libxml2.so.16]' "$work/reports/elf-dynamic.txt"
if grep -Eq 'TEXTREL|Shared library: \[libgst' "$work/reports/elf-dynamic.txt"; then echo 'ERROR: forbidden dynamic relocation/dependency'; exit 13; fi
python3 - "$work/reports/elf-versions.txt" <<'PY'
import re,sys
v=[tuple(map(int,x.split('.'))) for x in re.findall(r'Name: GLIBC_([0-9.]+)',open(sys.argv[1]).read())]
assert all(x<=(2,41) for x in v),v
print('LIBXSLT_ELF_GLIBC=PASS_MAX_2_41')
PY
export PKG_CONFIG_LIBDIR="$work/stage/usr/lib/pkgconfig" PKG_CONFIG_PATH='' PKG_CONFIG_SYSROOT_DIR="$work/stage"
v=$(pkg-config --modversion libxslt 2>&1) || { echo "ERROR: libxslt.pc unavailable: $v"; exit 14; }
echo "LIBXSLT_PKGCONFIG_VERSION=$v"
[[ "$v" == 1.1.43 ]] || { echo "ERROR: unexpected libxslt version $v"; exit 14; }
cat > "$work/consumer.c" <<'C'
#include <libxslt/xslt.h>
#include <libxslt/transform.h>
#include <libxslt/xsltutils.h>
#include <libxml/parser.h>
int fire4nix_libxslt_probe(void) {
 const char* s="<xsl:stylesheet xmlns:xsl='http://www.w3.org/1999/XSL/Transform' version='1.0'></xsl:stylesheet>";
 xmlDocPtr doc=xmlReadMemory(s,-1,"offline.xsl",NULL,XML_PARSE_NONET);
 if (!doc) return 0;
 xsltStylesheetPtr style=xsltParseStylesheetDoc(doc);
 if (!style) return 0;
 xsltFreeStylesheet(style);
 return 1;
}
C
"$cc" -O2 -mcpu=cortex-a35 -fPIC -shared -Wl,-z,defs \
 -I"$xml/usr/include/libxml2" -I"$work/stage/usr/include" \
 "$work/consumer.c" -L"$work/stage/usr/lib" -L"$xml/usr/lib" \
 -Wl,-rpath-link,"$xml/usr/lib" -lxslt -lxml2 \
 -o "$work/libfire4nix-xslt-probe.so"
readelf -h "$work/libfire4nix-xslt-probe.so" | grep -Eq 'Machine:.*AArch64'
readelf -d "$work/libfire4nix-xslt-probe.so" > "$work/reports/consumer-dynamic.txt"
grep -Fq 'Shared library: [libxslt.so.1]' "$work/reports/consumer-dynamic.txt"
grep -Fq 'Shared library: [libxml2.so.16]' "$work/reports/consumer-dynamic.txt"
{
 echo 'LIBXSLT_BUILD=PASS_REAL_ROCKNIX_AARCH64'
 echo 'LIBXSLT_VERSION=1.1.43'
 echo 'LIBXML2_DEPENDENCY=2.14.4'
 echo 'TARGET_EXECUTED=no'
 echo 'WEBKIT_BUILT=no'
 echo 'R36H_INSTALLABLE=no'
} | tee "$work/reports/result.txt"
cat "$work/reports/result.txt" >> "$GITHUB_STEP_SUMMARY"
