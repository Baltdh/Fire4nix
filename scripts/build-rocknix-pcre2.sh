#!/usr/bin/env bash
# Build PCRE2 target libraries with the genuine ROCKNIX compiler, no target execution.
set -euo pipefail
[[ ${GITHUB_ACTIONS:-} == true && $(id -u) != 0 && -n ${GITHUB_WORKSPACE:-} ]] || {
  echo 'ERROR: non-root CI only'; exit 4;
}
base=$GITHUB_WORKSPACE
sdk="$base/rocknix-source/build.ROCKNIX-RK3326.aarch64/toolchain"
recipe="$base/rocknix-source/packages/devel/pcre2/package.mk"
work="$base/pcre2-build"
[[ ! -e "$work" && ! -L "$work" ]] || exit 4
mkdir -p "$work"/{source,stage,reports}
report="$work/reports"
cc="$sdk/bin/aarch64-rocknix-linux-gnu-gcc"
[[ $("$cc" -dumpmachine) == aarch64-rocknix-linux-gnu ]]
[[ $(git -C "$base/rocknix-source" rev-parse HEAD) == 3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb ]]
expected=21547f3516120c75597e5b30a992e27a592a31950b5140e7b8bfde3f192033c4
grep -Fxq 'PKG_VERSION="10.45"' "$recipe"
grep -Fxq "PKG_SHA256=\"$expected\"" "$recipe"
curl --proto '=https' --proto-redir '=https' -fLsS --retry 2 --connect-timeout 15 --max-time 120 \
 https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.45/pcre2-10.45.tar.bz2 -o "$work/source.tar.bz2"
echo "$expected  $work/source.tar.bz2" | sha256sum -c -
tar -xjf "$work/source.tar.bz2" --strip-components=1 -C "$work/source"
cmake -S "$work/source" -B "$work/build" -G Ninja \
 -DCMAKE_TOOLCHAIN_FILE="$sdk/fire4nix-toolchain.cmake" \
 -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_INSTALL_LIBDIR=lib \
 -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
 -DBUILD_SHARED_LIBS=OFF -DBUILD_STATIC_LIBS=ON \
 -DPCRE2_BUILD_PCRE2_8=ON -DPCRE2_BUILD_PCRE2_16=ON -DPCRE2_BUILD_PCRE2_32=OFF \
 -DPCRE2_SUPPORT_JIT=ON -DPCRE2_BUILD_TESTS=OFF -DPCRE2_BUILD_PCRE2GREP=OFF \
 -DPCRE2_SUPPORT_LIBEDIT=OFF -DPCRE2_SUPPORT_LIBREADLINE=OFF \
 2>&1 | tee "$report/configure.log"
cmake --build "$work/build" --parallel 2 2>&1 | tee "$report/build.log"
DESTDIR="$work/stage" cmake --install "$work/build" 2>&1 | tee "$report/install.log"
stage="$work/stage"
export PKG_CONFIG_LIBDIR="$stage/usr/lib/pkgconfig" PKG_CONFIG_PATH='' PKG_CONFIG_SYSROOT_DIR="$stage"
for width in 8 16; do
 test -s "$stage/usr/lib/libpcre2-$width.a"
 [[ $(pkg-config --modversion "libpcre2-$width") == 10.45 ]]
 readelf -h "$stage/usr/lib/libpcre2-$width.a" > "$report/archive-$width.txt"
done
cp "$work/build/CMakeCache.txt" "$report/CMakeCache.txt"
for flag in PCRE2_SUPPORT_JIT PCRE2_BUILD_PCRE2_8 PCRE2_BUILD_PCRE2_16; do
 grep -Fxq "$flag:BOOL=ON" "$report/CMakeCache.txt"
done
python3 - "$report/archive-8.txt" "$report/archive-16.txt" <<'PY'
import re,sys
for path in sys.argv[1:]:
 s=open(path).read()
 classes=re.findall(r'Class:\s+(\S+)',s)
 machines=re.findall(r'Machine:\s+([^\n]+)',s)
 types=re.findall(r'Type:\s+(\S+)',s)
 assert classes and len(classes)==len(machines)==len(types)
 assert set(classes)=={'ELF64'} and set(machines)=={'AArch64'} and set(types)=={'REL'}
print('PCRE2_ARCHIVES=PASS_AARCH64_ELF64_REL_8_AND_16')
PY
cat > "$work/consumer.c" <<'C'
#define PCRE2_CODE_UNIT_WIDTH 0
#include <pcre2.h>
int fire4nix_pcre_probe(void) {
    int error;
    PCRE2_SIZE offset;
    PCRE2_UCHAR16 pattern16[] = { '^', 'a', '+', '$', 0 };
    pcre2_code_8 *a = pcre2_compile_8((PCRE2_SPTR8)"^a+$", PCRE2_ZERO_TERMINATED, 0, &error, &offset, 0);
    pcre2_code_16 *b = pcre2_compile_16(pattern16, PCRE2_ZERO_TERMINATED, 0, &error, &offset, 0);
    if (!a || !b) {
        pcre2_code_free_8(a); pcre2_code_free_16(b); return -1;
    }
    int ja = pcre2_jit_compile_8(a, PCRE2_JIT_COMPLETE);
    int jb = pcre2_jit_compile_16(b, PCRE2_JIT_COMPLETE);
    pcre2_code_free_8(a); pcre2_code_free_16(b);
    return ja || jb;
}
C
"$cc" -O2 -mcpu=cortex-a35 -fPIC -shared -Wl,-z,defs \
 -I"$stage/usr/include" "$work/consumer.c" \
 "$stage/usr/lib/libpcre2-8.a" "$stage/usr/lib/libpcre2-16.a" \
 -o "$work/libfire4nix-pcre-probe.so"
readelf -h "$work/libfire4nix-pcre-probe.so" > "$report/probe-header.txt"
readelf -d "$work/libfire4nix-pcre-probe.so" > "$report/probe-dynamic.txt"
readelf -V "$work/libfire4nix-pcre-probe.so" > "$report/probe-versions.txt"
readelf -Ws "$work/libfire4nix-pcre-probe.so" > "$report/probe-symbols.txt"
grep -Eq 'Machine:.*AArch64' "$report/probe-header.txt"
if grep -Eq 'TEXTREL|Shared library: \[libpcre2' "$report/probe-dynamic.txt"; then exit 8; fi
python3 - "$report/probe-versions.txt" "$report/probe-symbols.txt" <<'PY'
import re,sys
v=[tuple(map(int,n.split('.'))) for n in re.findall(r'Name: GLIBC_([0-9.]+)',open(sys.argv[1]).read())]
assert all(n<=(2,41) for n in v),v
symbols=open(sys.argv[2]).read().splitlines()
for width in (8,16):
 for api in ('pcre2_compile','pcre2_jit_compile'):
  name=f'{api}_{width}'
  assert any(len(p:=line.split())>=8 and p[6]!='UND' and p[7]==name for line in symbols),name
print('PCRE2_PROBE_GLIBC_MAX='+('.'.join(map(str,max(v))) if v else 'none'))
PY
{
 echo 'PCRE2_BUILD=PASS_REAL_ROCKNIX_AARCH64_STATIC_PIC_8_16'
 echo 'PCRE2_VERSION=10.45'
 echo 'PCRE2_JIT=COMPILED_AND_LINKED_NOT_EXECUTED'
 echo 'SHARED_CONSUMER_LINK=PASS_NO_UNRESOLVED_SYMBOLS'
 echo 'TARGET_EXECUTED=no'
 echo 'WEBKIT_BUILT=no'
 echo 'R36H_INSTALLABLE=no'
} | tee "$report/result.txt"
cat "$report/result.txt" >> "$GITHUB_STEP_SUMMARY"
