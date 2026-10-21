#!/usr/bin/env bash
# Verify a real ROCKNIX libjpeg-turbo 3.0.1 cross-build and merge its outputs
# with the seven existing target dependencies. Strictly host-side / no install.
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && "$(id -u)" != 0 && -n "${GITHUB_WORKSPACE:-}" ]] ||
  { echo 'ERROR: non-root CI runner only' >&2; exit 4; }
root="$GITHUB_WORKSPACE"
sdk="$root/rocknix-source/build.ROCKNIX-RK3326.aarch64/toolchain"
cc="$sdk/bin/aarch64-rocknix-linux-gnu-gcc"
old="$root/seven-artifact/seven-deps/stage"
added="$root/jpeg-target-stage"
dest="$root/eight-deps"
[[ "$("$cc" -dumpmachine)" == aarch64-rocknix-linux-gnu ]] ||
  { echo 'ERROR: wrong compiler target' >&2; exit 4; }
[[ "$(git -C "$root/rocknix-source" rev-parse HEAD)" == 3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb ]] ||
  { echo 'ERROR: wrong ROCKNIX commit' >&2; exit 4; }
[[ "$(git -C "$root/jpeg-source" rev-parse HEAD)" == ec32420f6b5dfa4e86883d42b209e8371e55aeb5 ]] ||
  { echo 'ERROR: source not pinned to libjpeg-turbo 3.0.1 release' >&2; exit 4; }
grep -Fxq 'PKG_VERSION="3.0.1"' "$root/rocknix-source/projects/ROCKNIX/packages/graphics/libjpeg-turbo/package.mk"
grep -Fxq 'PKG_VERSION="3.1.1"' "$root/rocknix-source/packages/graphics/libjpeg-turbo/package.mk"
grep -Fxq 'set(VERSION 3.0.1)' "$root/jpeg-source/CMakeLists.txt"
for f in "$old/usr/lib/libgio-2.0.so.0" "$old/usr/lib/libpng16.so.16" "$old/usr/lib/pkgconfig/glib-2.0.pc" \
         "$added/usr/lib/libjpeg.a" "$added/usr/lib/pkgconfig/libjpeg.pc" "$added/usr/include/jpeglib.h"; do
  [[ -s "$f" ]] || { echo "ERROR: missing actual target artifact: $f" >&2; exit 5; }
done
[[ ! -e "$dest" && ! -L "$dest" ]] || { echo 'ERROR: output stage already exists' >&2; exit 5; }
mkdir -p "$dest"/{stage,report,build}
stage="$dest/stage"
# Check the compiled JPEG shared library ELF/soname before integrating.
shopt -s nullglob
sofiles=( "$added"/usr/lib/libjpeg.so.* )
[[ "${#sofiles[@]}" -gt 0 ]] || { echo 'ERROR: no JPEG shared library' >&2; exit 5; }
real_so=''
for f in "${sofiles[@]}"; do
  if [[ -f "$f" && ! -L "$f" ]] && readelf -h "$f" | grep -Eq 'Machine:.*AArch64'; then
    real_so="$f"; break
  fi
done
[[ -n "$real_so" ]] || { echo 'ERROR: no AArch64 shared JPEG library' >&2; exit 5; }
readelf -h "$real_so" > "$dest/report/jpeg-elf-header.txt"
readelf -d "$real_so" > "$dest/report/jpeg-elf-dynamic.txt"
readelf -V "$real_so" > "$dest/report/jpeg-elf-versions.txt"
grep -Eq 'Class:.*ELF64' "$dest/report/jpeg-elf-header.txt"
grep -Eq 'Type:.*DYN' "$dest/report/jpeg-elf-header.txt"
grep -Fq 'Shared library:' "$dest/report/jpeg-elf-dynamic.txt" || true
if grep -Eq 'TEXTREL|Shared library: \[libgst' "$dest/report/jpeg-elf-dynamic.txt"; then
 echo 'ERROR: text relocations or GStreamer dependencies' >&2; exit 6
fi
python3 - "$dest/report/jpeg-elf-versions.txt" <<'PY'
from pathlib import Path
import re,sys
versions=[tuple(map(int,s.split('.'))) for s in re.findall(r'Name: GLIBC_([0-9]+\.[0-9]+)',Path(sys.argv[1]).read_text())]
if versions and max(versions)>(2,41): raise SystemExit(f'ERROR: GLIBC required {max(versions)} exceeds 2.41')
print('JPEG_GLIBC_ABI=PASS_MAX_2_41')
PY
# Artifacts are extracted from pinned, signed GitHub Actions runs. Even so,
# do not allow path escape or silent overwrites when merging source trees.
python3 - "$old" "$added" "$stage" <<'PY'
from pathlib import Path
import hashlib,shutil,sys
sources=[Path(x) for x in sys.argv[1:3]]
target=Path(sys.argv[3])
copied=0
for src in sources:
    for rel in ('usr/lib','usr/include'):
        root=src/rel
        if not root.is_dir(): raise SystemExit(f'ERROR: missing {root}')
        for path in sorted(root.rglob('*')):
            dest=target/path.relative_to(src)
            if path.is_symlink():
                link=path.readlink()
                if link.is_absolute() or '..' in link.parts:
                    raise SystemExit(f'ERROR: external symlink {path} -> {link}')
                if dest.is_symlink() and dest.readlink()==link: continue
                if dest.exists() or dest.is_symlink(): raise SystemExit(f'ERROR: symlink collision {dest}')
                dest.parent.mkdir(parents=True,exist_ok=True)
                dest.symlink_to(link)
            elif path.is_dir():
                if dest.is_symlink() or (dest.exists() and not dest.is_dir()):
                    raise SystemExit(f'ERROR: directory collision {dest}')
                dest.mkdir(parents=True,exist_ok=True)
            elif path.is_file():
                if dest.is_symlink() or (dest.exists() and not dest.is_file()):
                    raise SystemExit(f'ERROR: file collision {dest}')
                if dest.exists():
                    if hashlib.sha256(path.read_bytes()).digest()!=hashlib.sha256(dest.read_bytes()).digest():
                        raise SystemExit(f'ERROR: mismatched content {dest}')
                else:
                    dest.parent.mkdir(parents=True,exist_ok=True)
                    shutil.copy2(path,dest)
                    copied+=1
            else: raise SystemExit(f'ERROR: unsupported file type {path}')
print(f'EIGHT_TARGET_FILES_COPIED={copied}')
PY
# GitHub artifact ZIP archives can dereference symlinks; reconstruct the two
# linker names for the new JPEG library using its real ELF SONAME, not guesses.
python3 - "$stage/usr/lib" <<'PY'
from pathlib import Path
import re,subprocess,sys,hashlib
libs=Path(sys.argv[1])
candidates=[p for p in libs.glob('libjpeg.so*') if p.is_file() and not p.is_symlink()]
for real in candidates:
    hdr=subprocess.run(['readelf','-h',str(real)],capture_output=True,text=True)
    if 'AArch64' not in hdr.stdout: continue
    dyn=subprocess.run(['readelf','-d',str(real)],capture_output=True,text=True)
    got=re.findall(r'\(SONAME\).*\[([^\]]+)\]',dyn.stdout)
    if len(got)!=1: continue
    soname=got[0]
    if not re.fullmatch(r'libjpeg\.so\.[0-9]+',soname): continue
    for name in (soname,'libjpeg.so'):
        p=libs/name
        if p==real: continue
        if p.exists() or p.is_symlink():
            if p.is_symlink() and p.readlink()==Path(real.name): continue
            if p.is_file() and hashlib.sha256(p.read_bytes()).digest()==hashlib.sha256(real.read_bytes()).digest(): continue
            raise SystemExit(f'ERROR: unexpected JPEG linker target {p}')
        p.symlink_to(real.name)
    print('JPEG_SONAME='+soname)
    break
else: raise SystemExit('ERROR: no AArch64 JPEG ELF SONAME')
PY
export PKG_CONFIG_PATH='' PKG_CONFIG_LIBDIR="$stage/usr/lib/pkgconfig" PKG_CONFIG_SYSROOT_DIR="$stage"
for pc in libjpeg glib-2.0 gio-2.0 libpng16 sqlite3; do
  pkg-config --exists "$pc" || { echo "ERROR: target .pc missing $pc" >&2; exit 6; }
done
pkg-config --modversion libjpeg | tee "$dest/report/jpeg-pc-version.txt"
cat > "$dest/build/eight-consumer.c" <<'C'
#include <stdio.h>
#include <jpeglib.h>
#include <glib.h>
#include <gio/gio.h>
#include <png.h>
#include <zlib.h>
#include <sqlite3.h>
#include <libtasn1.h>
int fire4nix_eight_probe(void) {
 struct jpeg_decompress_struct jpg;
 struct jpeg_error_mgr err;
 jpg.err = jpeg_std_error(&err);
 jpeg_create_decompress(&jpg);
 jpeg_destroy_decompress(&jpg);
 GFile *file = g_file_new_for_path("/storage/fire4nix.html");
 if (file) g_object_unref(file);
 return png_access_version_number() && zlibVersion()[0] &&
        sqlite3_libversion()[0] && asn1_check_version(0);
}
C
"$cc" -O2 -mcpu=cortex-a35 -fPIC -shared -Wl,-z,defs \
 -I"$stage/usr/include" -I"$stage/usr/include/glib-2.0" -I"$stage/usr/lib/glib-2.0/include" \
 "$dest/build/eight-consumer.c" -L"$stage/usr/lib" \
 -Wl,-rpath-link,"$stage/usr/lib" \
 -ljpeg -lgio-2.0 -lgobject-2.0 -lglib-2.0 -lpng16 -lz -lsqlite3 -ltasn1 \
 -o "$dest/build/libeight-consumer.so"
readelf -h "$dest/build/libeight-consumer.so" > "$dest/report/consumer-elf-header.txt"
readelf -d "$dest/build/libeight-consumer.so" > "$dest/report/consumer-elf-dynamic.txt"
readelf -V "$dest/build/libeight-consumer.so" > "$dest/report/consumer-elf-versions.txt"
grep -Eq 'Class:.*ELF64' "$dest/report/consumer-elf-header.txt"
grep -Eq 'Machine:.*AArch64' "$dest/report/consumer-elf-header.txt"
for lib in libjpeg.so.8 libglib-2.0.so.0 libgio-2.0.so.0 \
           libpng16.so.16 libz.so.1 libsqlite3.so.0 libtasn1.so.6; do
 grep -Fq "Shared library: [$lib]" "$dest/report/consumer-elf-dynamic.txt" ||
  { echo "ERROR: consumer missing $lib" >&2; exit 6; }
done
python3 - "$dest/report/consumer-elf-versions.txt" <<'PY'
from pathlib import Path
import re,sys
versions=[tuple(map(int,s.split('.'))) for s in re.findall(r'Name: GLIBC_([0-9]+\.[0-9]+)',Path(sys.argv[1]).read_text())]
assert all(v<=(2,41) for v in versions),versions
print('EIGHT_CONSUMER_GLIBC=PASS_MAX_2_41')
PY
{
 echo 'JPEG_VERSION=3.0.1_ROCKNIX_PROJECT_EFFECTIVE'
 echo 'JPEG_SOURCE_SHA=ec32420f6b5dfa4e86883d42b209e8371e55aeb5'
 echo 'JPEG_TARGET_ELF=PASS_AARCH64'
 echo 'EIGHT_TARGET_STAGE=PASS_REAL_ROCKNIX_AARCH64'
 echo 'EIGHT_TARGET_CONSUMER_LINK=PASS_JPEG_GIO_GLIB_PNG_ZLIB_SQLITE_LIBTASN1'
 echo 'JPEG_SIMD_CONFIGURATION=ON_NEON_TARGET_TEST'
 echo 'TARGET_EXECUTED=no'
 echo 'WEBKIT_BUILT=no'
 echo 'R36H_INSTALLABLE=no'
} | tee "$dest/report/result.txt"
