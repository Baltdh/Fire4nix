#!/usr/bin/env bash
# Real ARM64 stage integration, no target execution or console modification.
set -euo pipefail
[[ ${GITHUB_ACTIONS:-} == true && $(id -u) != 0 && -n ${GITHUB_WORKSPACE:-} ]] || exit 4
root="$GITHUB_WORKSPACE"
six="$root/six-artifact/stage"
glib="$root/glib-artifact/glib-target/stage"
work="$root/seven-deps"
stage="$work/stage"
sdk="$root/rocknix-source/build.ROCKNIX-RK3326.aarch64/toolchain"
cc="$sdk/bin/aarch64-rocknix-linux-gnu-gcc"
[[ ! -e "$work" && ! -L "$work" ]] || exit 4
[[ $(git -C "$root/rocknix-source" rev-parse HEAD) == 3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb ]]
[[ $("$cc" -dumpmachine) == aarch64-rocknix-linux-gnu ]]
# GitHub Actions artifact zip does not preserve symbolic links. Reconstruct
# SONAME and development links only from actual regular AArch64 ELF files.
# Never follow external links, overwrite names or infer a library from a filename.
python3 - "$six" "$glib" <<'PY'
from pathlib import Path
import re,subprocess,sys
for root in map(Path,sys.argv[1:]):
 directory=root/'usr/lib'
 if not directory.is_dir(): raise SystemExit(f'missing library directory {directory}')
 count=0
 for f in sorted(directory.glob('lib*.so*')):
  if f.is_symlink() or not f.is_file(): continue
  head=subprocess.run(['readelf','-h',str(f)],capture_output=True,text=True,check=False)
  if head.returncode or not re.search(r'Machine:\s+AArch64',head.stdout): continue
  dyn=subprocess.run(['readelf','-d',str(f)],capture_output=True,text=True,check=False)
  found=re.findall(r'\(SONAME\).*\[([^\]]+)\]',dyn.stdout)
  if len(found)!=1: continue
  soname=found[0]
  if '/' in soname or '..' in soname or not soname.startswith('lib'): raise SystemExit(f'unsafe SONAME {soname}')
  if not f.name.startswith(soname): continue
  names=[soname]
  if '.so' in soname: names.append(soname.split('.so',1)[0]+'.so')
  for name in names:
   dest=directory/name
   if dest==f: continue
   if dest.exists() or dest.is_symlink():
    if dest.is_symlink() and dest.readlink()==Path(f.name): continue
    raise SystemExit(f'link name already exists {dest}')
   dest.symlink_to(f.name)
   count+=1
 print(f'RESTORED_LINKS={root.name}:{count}')
PY
for lib in "$six/usr/lib/libffi.a" "$six/usr/lib/libpcre2-8.a" \
  "$six/usr/lib/libpcre2-16.a" "$glib/usr/lib/libglib-2.0.so.0" \
  "$glib/usr/lib/libgobject-2.0.so.0" "$glib/usr/lib/libgio-2.0.so.0" \
  "$glib/usr/lib/libgmodule-2.0.so.0"; do
  test -s "$lib" || { echo "ERROR: absent target artifact $lib"; exit 4; }
done
mkdir -p "$stage" "$work/build" "$work/report"
python3 - "$six" "$glib" "$stage" <<'PY'
from pathlib import Path
import hashlib, shutil, sys
sources=list(map(Path,sys.argv[1:3])); dst=Path(sys.argv[3])
for src in sources:
 for rel in ('usr/include', 'usr/lib'):
  root=src/rel
  if not root.is_dir(): raise SystemExit(f'missing directory {root}')
  for f in sorted(root.rglob('*')):
   d=dst/f.relative_to(src)
   if f.is_symlink():
    link=f.readlink()
    if link.is_absolute() or '..' in link.parts: raise SystemExit(f'unsafe symlink {f}')
    if d.is_symlink() and d.readlink()==link: continue
    if d.exists() or d.is_symlink(): raise SystemExit(f'file collision {d}')
    d.parent.mkdir(parents=True,exist_ok=True); d.symlink_to(link)
   elif f.is_dir():
    if d.is_symlink() or (d.exists() and not d.is_dir()): raise SystemExit(f'dir collision {d}')
    d.mkdir(parents=True,exist_ok=True)
   elif f.is_file():
    if d.is_symlink() or (d.exists() and not d.is_file()): raise SystemExit(f'file collision {d}')
    if d.exists():
     if hashlib.sha256(f.read_bytes()).digest()!=hashlib.sha256(d.read_bytes()).digest(): raise SystemExit(f'content collision {d}')
    else:
     d.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(f,d)
   else: raise SystemExit(f'unsupported path {f}')
print('SEVEN_STAGE_MERGE=PASS_COLLISION_SAFE')
PY
export PKG_CONFIG_LIBDIR="$stage/usr/lib/pkgconfig" PKG_CONFIG_PATH='' PKG_CONFIG_SYSROOT_DIR="$stage"
for pc in glib-2.0 gio-2.0 gobject-2.0 gmodule-2.0; do
  [[ $(pkg-config --modversion "$pc") == 2.85.1 ]] || exit 5
done
for pc in libpcre2-8 libpcre2-16 libffi; do pkg-config --exists "$pc" || exit 5; done
cat > "$work/build/consumer.c" <<'C'
#include <glib.h>
#include <glib-object.h>
#include <gio/gio.h>
#include <gmodule.h>
#include <png.h>
#include <zlib.h>
#include <sqlite3.h>
#include <libtasn1.h>
int fire4nix_seven_probe(void) {
 GError *error=0;
 GRegex *regex=g_regex_new("r36h",0,0,&error);
 if (!regex) { if(error) g_error_free(error); return -1; }
 gboolean matched=g_regex_match(regex,"fire4nix-r36h",0,0);
 g_regex_unref(regex);
 GFile *file=g_file_new_for_path("/storage/fire4nix.html");
 if(!file) return -2;
 g_object_unref(file);
 return matched && g_module_supported() && png_access_version_number()==10640 &&
        zlibVersion()[0] && sqlite3_libversion()[0] && asn1_check_version(0);
}
C
"$cc" -O2 -mcpu=cortex-a35 -fPIC -shared -Wl,-z,defs \
 -I"$stage/usr/include" -I"$stage/usr/include/glib-2.0" \
 -I"$stage/usr/lib/glib-2.0/include" "$work/build/consumer.c" \
 -L"$stage/usr/lib" -Wl,-rpath-link,"$stage/usr/lib" \
 -lgio-2.0 -lgobject-2.0 -lgmodule-2.0 -lglib-2.0 \
 -lpng16 -lz -lsqlite3 -ltasn1 -o "$work/build/libseven-consumer.so"
readelf -h "$work/build/libseven-consumer.so" > "$work/report/elf-header.txt"
readelf -d "$work/build/libseven-consumer.so" > "$work/report/elf-dynamic.txt"
readelf -V "$work/build/libseven-consumer.so" > "$work/report/elf-versions.txt"
grep -Eq 'Class:.*ELF64' "$work/report/elf-header.txt"
grep -Eq 'Machine:.*AArch64' "$work/report/elf-header.txt"
for name in libglib-2.0.so.0 libgobject-2.0.so.0 libgio-2.0.so.0 \
 libgmodule-2.0.so.0 libpng16.so.16 libz.so.1 libsqlite3.so.0 libtasn1.so.6; do
  grep -Fq "Shared library: [$name]" "$work/report/elf-dynamic.txt" || {
    echo "ERROR: absent $name in DT_NEEDED"; exit 6; }
done
if grep -Eq 'TEXTREL|Shared library: \[libgst' "$work/report/elf-dynamic.txt"; then exit 6; fi
python3 - "$work/report/elf-versions.txt" <<'PY'
import re,sys
s=open(sys.argv[1]).read()
v=[tuple(map(int,x.split('.'))) for x in re.findall(r'Name: GLIBC_([0-9.]+)',s)]
assert all(x<=(2,41) for x in v),v
print('SEVEN_CONSUMER_GLIBC=PASS_MAX_2_41')
PY
{
 echo 'SEVEN_DEPENDENCY_STAGE=PASS_REAL_ROCKNIX_AARCH64'
 echo 'SEVEN_CONSUMER_LINK=PASS_GLIB_GOBJECT_GIO_GMODULE'
 echo 'TARGET_EXECUTED=no'
 echo 'WEBKIT_BUILT=no'
 echo 'R36H_INSTALLABLE=no'
} | tee "$work/report/result.txt"
cat "$work/report/result.txt" >> "$GITHUB_STEP_SUMMARY"
