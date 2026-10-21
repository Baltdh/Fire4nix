#!/usr/bin/env bash
# Extend the real four-library stage with ROCKNIX static PIC libffi.
set -euo pipefail
[[ ${GITHUB_ACTIONS:-} == true && $(id -u) != 0 && -n ${GITHUB_WORKSPACE:-} ]] || {
  echo 'ERROR: non-root CI only'; exit 4;
}
bash "$(dirname "$0")/verify-four-rocknix-deps.sh" --check
work="$GITHUB_WORKSPACE/four-rocknix"
stage="$work/stage"
ffi="$GITHUB_WORKSPACE/libffi-artifact/stage"
test -s "$ffi/usr/lib/libffi.a"
test -s "$ffi/usr/lib/pkgconfig/libffi.pc"
# Collision-safe merge of the fifth independently compiled target artifact.
python3 - "$ffi" "$stage" <<'PY'
from pathlib import Path
import hashlib, shutil, sys
src, dst=map(Path,sys.argv[1:])
for f in sorted((src/'usr').rglob('*')):
    d=dst/f.relative_to(src)
    if f.is_symlink():
        link=f.readlink()
        if link.is_absolute() or '..' in link.parts:
            raise SystemExit(f'unsafe link: {f}')
        if d.is_symlink() and d.readlink()==link: continue
        if d.exists() or d.is_symlink(): raise SystemExit(f'collision: {d}')
        d.parent.mkdir(parents=True,exist_ok=True)
        d.symlink_to(link)
    elif f.is_dir():
        if d.is_symlink() or (d.exists() and not d.is_dir()): raise SystemExit(f'collision: {d}')
        d.mkdir(parents=True,exist_ok=True)
    elif f.is_file():
        if d.is_symlink() or (d.exists() and not d.is_file()): raise SystemExit(f'collision: {d}')
        if d.exists():
            if hashlib.sha256(f.read_bytes()).digest()!=hashlib.sha256(d.read_bytes()).digest():
                raise SystemExit(f'content collision: {d}')
        else:
            d.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(f,d)
    else: raise SystemExit(f'unsupported file: {f}')
PY
export PKG_CONFIG_LIBDIR="$stage/usr/lib/pkgconfig" PKG_CONFIG_PATH='' PKG_CONFIG_SYSROOT_DIR="$stage"
[[ $(pkg-config --modversion libffi) == 3.5.1 ]]
read -r -a ffi_cflags <<< "$(pkg-config --cflags libffi)"
sdk="$GITHUB_WORKSPACE/rocknix-source/build.ROCKNIX-RK3326.aarch64/toolchain"
cat > "$work/build/five-consumer.c" <<'C'
#include <ffi.h>
#include <png.h>
#include <zlib.h>
#include <sqlite3.h>
#include <libtasn1.h>
static int identity(int value) { return value; }
int fire4nix_five_probe(void) {
    ffi_cif cif;
    ffi_type *types[] = { &ffi_type_sint };
    int value = 42;
    ffi_arg result = 0;
    void *values[] = { &value };
    if (ffi_prep_cif(&cif, FFI_DEFAULT_ABI, 1, &ffi_type_sint, types) != FFI_OK) return -1;
    ffi_call(&cif, FFI_FN(identity), &result, values);
    return result == 42 && png_access_version_number() == 10640 &&
           zlibVersion()[0] && sqlite3_libversion()[0] && asn1_check_version(0);
}
C
"$sdk/bin/aarch64-rocknix-linux-gnu-gcc" -O2 -mcpu=cortex-a35 -fPIC -shared \
  -Wl,-z,defs -Wl,-Map,"$work/report/five-link.map" \
  "${ffi_cflags[@]}" -I"$stage/usr/include" \
  "$work/build/five-consumer.c" "$stage/usr/lib/libffi.a" \
  -L"$stage/usr/lib" -Wl,-rpath-link,"$stage/usr/lib" \
  -lpng16 -lz -lsqlite3 -ltasn1 -o "$work/build/libfive-consumer.so"
readelf -h "$work/build/libfive-consumer.so" > "$work/report/five-header.txt"
readelf -d "$work/build/libfive-consumer.so" > "$work/report/five-dynamic.txt"
readelf -V "$work/build/libfive-consumer.so" > "$work/report/five-versions.txt"
readelf -Ws "$work/build/libfive-consumer.so" > "$work/report/five-symbols.txt"
grep -Eq 'Class:.*ELF64' "$work/report/five-header.txt"
grep -Eq 'Machine:.*AArch64' "$work/report/five-header.txt"
for soname in libpng16.so.16 libz.so.1 libsqlite3.so.0 libtasn1.so.6; do
  grep -Fq "Shared library: [$soname]" "$work/report/five-dynamic.txt"
done
if grep -Eq 'TEXTREL|Shared library: \[libffi|Shared library: \[libgst' "$work/report/five-dynamic.txt"; then
  echo 'ERROR: incompatible five-library consumer'; exit 6
fi
python3 - "$work/report/five-symbols.txt" "$work/report/five-versions.txt" <<'PY'
import re,sys
symbols=open(sys.argv[1]).read().splitlines()
for name in ('ffi_call','ffi_prep_cif'):
    assert any(len(p:=line.split())>=8 and p[6]!='UND' and p[7]==name for line in symbols), name
versions=[tuple(map(int,v.split('.'))) for v in re.findall(r'Name: GLIBC_([0-9.]+)',open(sys.argv[2]).read())]
assert all(v <= (2,41) for v in versions), versions
print('FIVE_CONSUMER_GLIBC_MAX=' + ('.'.join(map(str,max(versions))) if versions else 'none'))
PY
# The map proves the static libffi objects came from the private stage.
grep -Fq "$stage/usr/lib/libffi.a(" "$work/report/five-link.map"
{
 echo 'FIVE_DEPENDENCY_STAGE=PASS_REAL_ROCKNIX_AARCH64'
 echo 'FIVE_CONSUMER_LINK=PASS_FOUR_SHARED_PLUS_STATIC_LIBFFI'
 echo 'LIBRARIES=zlib_1.3.1,sqlite_3.50.2,libtasn1_4.21.0,libpng_1.6.40,libffi_3.5.1'
 echo 'TARGET_EXECUTED=no'
 echo 'WEBKIT_BUILT=no'
 echo 'R36H_INSTALLABLE=no'
} | tee "$work/report/five-acceptance.txt"
(cd "$stage" && find usr -type f -print0 | sort -z | xargs -0 sha256sum) > "$work/report/five-stage-sha256sums.txt"
cat "$work/report/five-acceptance.txt" >> "$GITHUB_STEP_SUMMARY"
