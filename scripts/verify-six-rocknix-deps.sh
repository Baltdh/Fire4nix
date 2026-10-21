#!/usr/bin/env bash
set -euo pipefail
[[ ${GITHUB_ACTIONS:-} == true && $(id -u) != 0 && -n ${GITHUB_WORKSPACE:-} ]] || { echo 'ERROR: CI non-root only' >&2; exit 4; }
bash "$(dirname "$0")/verify-five-rocknix-deps.sh" --check
work="$GITHUB_WORKSPACE/four-rocknix"
stage="$work/stage"
pcre="$GITHUB_WORKSPACE/pcre2-artifact/stage"
for n in 8 16; do
 test -s "$pcre/usr/lib/libpcre2-$n.a"
 test -s "$pcre/usr/lib/pkgconfig/libpcre2-$n.pc"
done
python3 - "$pcre" "$stage" <<'PY'
from pathlib import Path
import hashlib,shutil,sys
src,dst=map(Path,sys.argv[1:])
for root in ('usr/lib','usr/include'):
 for f in sorted((src/root).rglob('*')):
  d=dst/f.relative_to(src)
  if f.is_symlink():
   link=f.readlink()
   if link.is_absolute() or '..' in link.parts: raise SystemExit(f'unsafe symlink {f}')
   if d.is_symlink() and d.readlink()==link: continue
   if d.exists() or d.is_symlink(): raise SystemExit(f'collision {d}')
   d.parent.mkdir(parents=True,exist_ok=True); d.symlink_to(link)
  elif f.is_dir():
   if d.is_symlink() or (d.exists() and not d.is_dir()): raise SystemExit(f'collision {d}')
   d.mkdir(parents=True,exist_ok=True)
  elif f.is_file():
   if d.is_symlink() or (d.exists() and not d.is_file()): raise SystemExit(f'collision {d}')
   if d.exists():
    if hashlib.sha256(f.read_bytes()).digest()!=hashlib.sha256(d.read_bytes()).digest(): raise SystemExit(f'content collision {d}')
   else:
    d.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(f,d)
  else: raise SystemExit(f'unsupported {f}')
PY
export PKG_CONFIG_LIBDIR="$stage/usr/lib/pkgconfig" PKG_CONFIG_PATH='' PKG_CONFIG_SYSROOT_DIR="$stage"
for width in 8 16; do
 [[ $(pkg-config --modversion libpcre2-$width) == 10.45 ]]
done
sdk="$GITHUB_WORKSPACE/rocknix-source/build.ROCKNIX-RK3326.aarch64/toolchain"
cat > "$work/build/six-consumer.c" <<'C'
#define PCRE2_CODE_UNIT_WIDTH 0
#include <pcre2.h>
#include <ffi.h>
#include <png.h>
#include <zlib.h>
#include <sqlite3.h>
#include <libtasn1.h>
static int identity(int x) { return x; }
int fire4nix_six_probe(void) {
 ffi_cif cif;
 ffi_type *args[] = { &ffi_type_sint };
 int value = 42;
 ffi_arg result = 0;
 void *values[] = { &value };
 int err;
 PCRE2_SIZE off;
 PCRE2_UCHAR16 pattern[] = {'a','+',0};
 pcre2_code_8 *a = pcre2_compile_8((PCRE2_SPTR8)"a+",PCRE2_ZERO_TERMINATED,0,&err,&off,0);
 pcre2_code_16 *b = pcre2_compile_16(pattern,PCRE2_ZERO_TERMINATED,0,&err,&off,0);
 if (!a || !b) { pcre2_code_free_8(a); pcre2_code_free_16(b); return -1; }
 int ja=pcre2_jit_compile_8(a,PCRE2_JIT_COMPLETE);
 int jb=pcre2_jit_compile_16(b,PCRE2_JIT_COMPLETE);
 pcre2_code_free_8(a); pcre2_code_free_16(b);
 if (ffi_prep_cif(&cif,FFI_DEFAULT_ABI,1,&ffi_type_sint,args)!=FFI_OK) return -2;
 ffi_call(&cif,FFI_FN(identity),&result,values);
 return result==42 && !ja && !jb && png_access_version_number()==10640 &&
        zlibVersion()[0] && sqlite3_libversion()[0] && asn1_check_version(0);
}
C
"$sdk/bin/aarch64-rocknix-linux-gnu-gcc" -O2 -mcpu=cortex-a35 -fPIC -shared -Wl,-z,defs \
 -Wl,-Map,"$work/report/six-link.map" -I"$stage/usr/include" \
 "$work/build/six-consumer.c" "$stage/usr/lib/libffi.a" \
 "$stage/usr/lib/libpcre2-8.a" "$stage/usr/lib/libpcre2-16.a" \
 -L"$stage/usr/lib" -Wl,-rpath-link,"$stage/usr/lib" \
 -lpng16 -lz -lsqlite3 -ltasn1 -o "$work/build/libsix-consumer.so"
readelf -h "$work/build/libsix-consumer.so" > "$work/report/six-header.txt"
readelf -d "$work/build/libsix-consumer.so" > "$work/report/six-dynamic.txt"
readelf -Ws "$work/build/libsix-consumer.so" > "$work/report/six-symbols.txt"
readelf -V "$work/build/libsix-consumer.so" > "$work/report/six-versions.txt"
grep -Eq 'Class:.*ELF64' "$work/report/six-header.txt"
grep -Eq 'Machine:.*AArch64' "$work/report/six-header.txt"
for soname in libpng16.so.16 libz.so.1 libsqlite3.so.0 libtasn1.so.6; do
 grep -Fq "Shared library: [$soname]" "$work/report/six-dynamic.txt"
done
if grep -Eq 'TEXTREL|Shared library: \[libffi|Shared library: \[libpcre2|Shared library: \[libgst' "$work/report/six-dynamic.txt"; then
 echo 'ERROR: forbidden dynamic dependency'; exit 6
fi
python3 - "$work/report/six-symbols.txt" "$work/report/six-versions.txt" <<'PY'
import re,sys
symbols=open(sys.argv[1]).read().splitlines()
for name in ('ffi_call','ffi_prep_cif','pcre2_compile_8','pcre2_compile_16','pcre2_jit_compile_8','pcre2_jit_compile_16'):
 assert any(len(p:=line.split())>=8 and p[6]!='UND' and p[7]==name for line in symbols),name
versions=[tuple(map(int,x.split('.'))) for x in re.findall(r'Name: GLIBC_([0-9.]+)',open(sys.argv[2]).read())]
assert all(v<=(2,41) for v in versions),versions
print('SIX_CONSUMER_GLIBC_MAX='+('.'.join(map(str,max(versions))) if versions else 'none'))
PY
for archive in libffi.a libpcre2-8.a libpcre2-16.a; do
 grep -Fq "$stage/usr/lib/$archive(" "$work/report/six-link.map"
done
{
 echo 'SIX_DEPENDENCY_STAGE=PASS_REAL_ROCKNIX_AARCH64'
 echo 'SIX_CONSUMER_LINK=PASS_FOUR_SHARED_PLUS_THREE_STATIC_ARCHIVES'
 echo 'LIBRARIES=zlib_1.3.1,sqlite_3.50.2,libtasn1_4.21.0,libpng_1.6.40,libffi_3.5.1,pcre2_10.45'
 echo 'TARGET_EXECUTED=no'
 echo 'WEBKIT_BUILT=no'
 echo 'R36H_INSTALLABLE=no'
} | tee "$work/report/six-acceptance.txt"
cat "$work/report/six-acceptance.txt" >> "$GITHUB_STEP_SUMMARY"
