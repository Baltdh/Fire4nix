#!/usr/bin/env bash
# Build the pinned ROCKNIX libffi recipe into a private stage; never run target code.
set -euo pipefail
[[ ${GITHUB_ACTIONS:-} == true && $(id -u) != 0 && -n ${GITHUB_WORKSPACE:-} ]] || {
  echo 'ERROR: non-root CI only'; exit 4;
}
base=$GITHUB_WORKSPACE
sdk="$base/rocknix-source/build.ROCKNIX-RK3326.aarch64/toolchain"
recipe="$base/rocknix-source/packages/devel/libffi"
work="$base/libffi-build"
[[ ! -e "$work" && ! -L "$work" ]] || exit 4
mkdir -p "$work"/{source,build,stage,reports}
report="$work/reports"
cc="$sdk/bin/aarch64-rocknix-linux-gnu-gcc"
[[ $("$cc" -dumpmachine) == aarch64-rocknix-linux-gnu ]]
[[ $(git -C "$base/rocknix-source" rev-parse HEAD) == 3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb ]]
expected=f99eb68a67c7d54866b7706af245e87ba060d419a062474b456d3bc8d4abdbd1
grep -Fxq 'PKG_VERSION="3.5.1"' "$recipe/package.mk"
grep -Fxq "PKG_SHA256=\"$expected\"" "$recipe/package.mk"
curl --proto '=https' --proto-redir '=https' -fLsS --retry 2 --connect-timeout 15 --max-time 120 \
  https://github.com/libffi/libffi/releases/download/v3.5.1/libffi-3.5.1.tar.gz -o "$work/source.tar.gz"
echo "$expected  $work/source.tar.gz" | sha256sum -c -
tar -xzf "$work/source.tar.gz" --strip-components=1 -C "$work/source"
cd "$work/source"
for patchfile in "$recipe"/patches/*.patch; do
  patch --batch --forward -p1 < "$patchfile"
done
# ROCKNIX uses its autotools framework after patching Makefile.am.
autoreconf -fi > "$report/autoreconf.log" 2>&1 || { tail -n 80 "$report/autoreconf.log"; exit 5; }
cd "$work/build"
CC="$cc" AR="$sdk/bin/aarch64-rocknix-linux-gnu-ar" \
RANLIB="$sdk/bin/aarch64-rocknix-linux-gnu-ranlib" \
CFLAGS='-O2 -mcpu=cortex-a35 -fPIC' \
  "$work/source/configure" --build="$("$work/source/config.guess")" \
  --host=aarch64-rocknix-linux-gnu --prefix=/usr --libdir=/usr/lib \
  --disable-debug --enable-static --disable-shared --with-pic \
  --enable-structs --enable-raw-api --disable-purify-safety --with-gnu-ld \
  > "$report/configure.log" 2>&1 || { tail -n 80 "$report/configure.log"; exit 6; }
make -j2 > "$report/build.log" 2>&1 || { tail -n 80 "$report/build.log"; exit 7; }
make install DESTDIR="$work/stage" > "$report/install.log" 2>&1
stage="$work/stage"
test -s "$stage/usr/lib/libffi.a"
test -s "$stage/usr/lib/pkgconfig/libffi.pc"
export PKG_CONFIG_LIBDIR="$stage/usr/lib/pkgconfig" PKG_CONFIG_PATH='' PKG_CONFIG_SYSROOT_DIR="$stage"
[[ $(pkg-config --modversion libffi) == 3.5.1 ]]
# Every archive member must be an AArch64 ELF64 relocatable object.
readelf -h "$stage/usr/lib/libffi.a" > "$report/archive-headers.txt"
python3 - "$report/archive-headers.txt" <<'PY'
import re, sys
s=open(sys.argv[1]).read()
classes=re.findall(r'Class:\s+(\S+)',s)
machines=re.findall(r'Machine:\s+([^\n]+)',s)
types=re.findall(r'Type:\s+(\S+)',s)
assert classes and len(classes)==len(machines)==len(types)
assert set(classes)=={'ELF64'} and set(machines)=={'AArch64'} and set(types)=={'REL'}
print('LIBFFI_ARCHIVE_MEMBERS=PASS_AARCH64_ELF64_REL')
PY
cat > "$work/consumer.c" <<'C'
#include <ffi.h>
static int identity(int value) { return value; }
int fire4nix_ffi_probe(void) {
    ffi_cif cif;
    ffi_type *types[] = { &ffi_type_sint };
    int value = 42;
    ffi_arg result = 0;
    void *values[] = { &value };
    if (ffi_prep_cif(&cif, FFI_DEFAULT_ABI, 1, &ffi_type_sint, types) != FFI_OK) return -1;
    ffi_call(&cif, FFI_FN(identity), &result, values);
    return (int) result;
}
C
read -r -a cflags <<< "$(pkg-config --cflags libffi)"
"$cc" -O2 -fPIC -shared -Wl,-z,defs "${cflags[@]}" "$work/consumer.c" \
  "$stage/usr/lib/libffi.a" -o "$work/libfire4nix-ffi-probe.so"
readelf -h "$work/libfire4nix-ffi-probe.so" > "$report/probe-header.txt"
readelf -d "$work/libfire4nix-ffi-probe.so" > "$report/probe-dynamic.txt"
readelf -V "$work/libfire4nix-ffi-probe.so" > "$report/probe-versions.txt"
grep -Eq 'Machine:.*AArch64' "$report/probe-header.txt"
if grep -Eq 'TEXTREL|Shared library: \[libffi' "$report/probe-dynamic.txt"; then
  echo 'ERROR: static PIC probe gained text relocations or shared libffi dependency'; exit 8
fi
python3 - "$report/probe-versions.txt" <<'PY'
import re, sys
versions=[tuple(map(int,v.split('.'))) for v in re.findall(r'Name: GLIBC_([0-9.]+)',open(sys.argv[1]).read())]
assert all(v <= (2,41) for v in versions), versions
print('LIBFFI_PROBE_GLIBC_MAX=' + ('.'.join(map(str,max(versions))) if versions else 'none'))
PY
{
 echo 'LIBFFI_BUILD=PASS_REAL_ROCKNIX_AARCH64_STATIC_PIC'
 echo 'LIBFFI_VERSION=3.5.1'
 echo 'SHARED_CONSUMER_LINK=PASS_NO_UNRESOLVED_SYMBOLS'
 echo 'ROCKNIX_RECIPE_PATCHES=applied'
 echo 'TARGET_EXECUTED=no'
 echo 'WEBKIT_BUILT=no'
 echo 'R36H_INSTALLABLE=no'
} | tee "$report/result.txt"
cat "$report/result.txt" >> "$GITHUB_STEP_SUMMARY"
