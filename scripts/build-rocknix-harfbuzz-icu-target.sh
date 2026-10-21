#!/usr/bin/env bash
# REAL ROCKNIX AArch64 HarfBuzz 11.2.1 + ICU 74.1, isolated GitHub Actions.
# No AArch64 target code executed on host or handheld.
set -euo pipefail
[[ ${GITHUB_ACTIONS:-} == true && $(id -u) != 0 && -n ${GITHUB_WORKSPACE:-} ]] || { echo "ERROR: CI non-root only"; exit 4; }
root="$GITHUB_WORKSPACE"
sdk="$root/rocknix-source/build.ROCKNIX-RK3326.aarch64/toolchain"
font="$root/fontconfig-artifact/fontconfig-target/stage"
cairo="$root/cairo-artifact/stage"
icu="$root/icu-artifact/icu74-target/stage"
work="$root/harfbuzz-icu-target"
[[ ! -e "$work" && ! -L "$work" ]] || { echo "ERROR: existing output"; exit 4; }
mkdir -p "$work"/{source,stage,deps,reports}
[[ $(git -C "$root/rocknix-source" rev-parse HEAD) == 3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb ]]
cc="$sdk/bin/aarch64-rocknix-linux-gnu-gcc"
[[ $("$cc" -dumpmachine) == aarch64-rocknix-linux-gnu ]]
recipe="$root/rocknix-source/packages/graphics/harfbuzz/package.mk"
hash=093714c8548a285094685f0bdc999e202d666b59eeb3df2ff921ab68b8336a49
grep -Fxq 'PKG_VERSION="11.2.1"' "$recipe"
grep -Fxq "PKG_SHA256=\"$hash\"" "$recipe"
grep -q -- '-Dicu=disabled' "$recipe" || { echo 'ERROR: upstream ICU default changed'; exit 4; }
grep -Fxq 'ICU74_BUILD=PASS_REAL_ROCKNIX_AARCH64' "$root/icu-artifact/icu74-target/reports/result.txt"
grep -Fxq 'CAIRO_TARGET_BUILD=PASS_REAL_ROCKNIX_AARCH64' "$root/cairo-artifact/reports/acceptance.txt"
grep -Fxq 'FONTCONFIG_BUILD=PASS_REAL_ROCKNIX_AARCH64' "$root/fontconfig-artifact/fontconfig-target/reports/acceptance.txt"
for f in "$icu/usr/lib/libicuuc.so.74" "$icu/usr/lib/libicui18n.so.74" \
 "$font/usr/lib/libfreetype.so.6" "$font/usr/lib/libglib-2.0.so.0" \
 "$cairo/usr/lib/libcairo.so.2"; do
 test -s "$f" || { echo "ERROR: missing target dependency $f"; exit 5; }
 readelf -h "$f" | grep -Eq 'Machine:.*AArch64'
done
# Verified, collision-safe target stage merger: identical overlaps only.
python3 - "$font" "$cairo" "$icu" "$work/deps" <<'PY'
from pathlib import Path
import sys,hashlib,shutil
inputs=list(map(Path,sys.argv[1:4]))
dst=Path(sys.argv[4])
for src in inputs:
 for section in ("usr/include","usr/lib"):
  source=src/section
  if not source.is_dir(): raise SystemExit(f"missing source path {source}")
  for f in sorted(source.rglob("*")):
   d=dst/f.relative_to(src)
   if f.is_dir() and not f.is_symlink():
    if d.is_symlink() or (d.exists() and not d.is_dir()): raise SystemExit(f"directory collision {d}")
    d.mkdir(parents=True,exist_ok=True)
   elif f.is_symlink():
    link=f.readlink()
    if link.is_absolute() or ".." in link.parts: raise SystemExit(f"unsafe link {f}")
    if d.is_symlink() and d.readlink()==link: continue
    if d.exists() or d.is_symlink():
     if d.is_file() and not d.is_symlink() and f.resolve().is_file():
      if hashlib.sha256(d.read_bytes()).digest()==hashlib.sha256(f.resolve().read_bytes()).digest(): continue
     raise SystemExit(f"unsafe link collision {d}")
    d.parent.mkdir(parents=True,exist_ok=True)
    d.symlink_to(link)
   elif f.is_file():
    if d.is_symlink():
     if d.resolve().is_file() and hashlib.sha256(d.resolve().read_bytes()).digest()==hashlib.sha256(f.read_bytes()).digest(): continue
     raise SystemExit(f"file collides with symlink {d}")
    if d.exists():
     if not d.is_file() or hashlib.sha256(d.read_bytes()).digest()!=hashlib.sha256(f.read_bytes()).digest(): raise SystemExit(f"content collision {d}")
    else:
     d.parent.mkdir(parents=True,exist_ok=True)
     shutil.copy2(f,d)
   else: raise SystemExit(f"unsupported path {f}")
print("HARFBUZZ_DEPS=PASS_COLLISION_SAFE")
PY
sysroot="$sdk/aarch64-rocknix-linux-gnu/sysroot"
export PKG_CONFIG_PATH=''
export PKG_CONFIG_LIBDIR="$work/deps/usr/lib/pkgconfig:$sysroot/usr/lib/pkgconfig:$sysroot/usr/share/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$work/deps"
for p in icu-uc icu-i18n glib-2.0 freetype2 cairo cairo-ft; do
 pkg-config --exists "$p" || { echo "ERROR: missing target pkgconfig $p"; exit 5; }
 echo "TARGET_PKG=$p:$(pkg-config --modversion "$p")"
done
[[ $(pkg-config --modversion icu-uc) == 74.1 ]]
echo 'HARFBUZZ_SOURCE=DOWNLOAD'
curl -fLsS --proto '=https' --proto-redir '=https' --retry 2 --connect-timeout 20 --max-time 180 \
 "https://github.com/harfbuzz/harfbuzz/releases/download/11.2.1/harfbuzz-11.2.1.tar.xz" -o "$work/src.tar.xz"
echo "$hash  $work/src.tar.xz" | sha256sum --check
tar -xJf "$work/src.tar.xz" --strip-components=1 -C "$work/source"
test -s "$work/source/meson.build"
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
sys_root = '$sysroot'
pkg_config_libdir = ['$work/deps/usr/lib/pkgconfig', '$sysroot/usr/lib/pkgconfig']
[built-in options]
c_args = ['-mcpu=cortex-a35','-mno-outline-atomics','-I$work/deps/usr/include','-I$work/deps/usr/include/freetype2','-I$work/deps/usr/include/glib-2.0','-I$work/deps/usr/lib/glib-2.0/include']
cpp_args = ['-mcpu=cortex-a35','-mno-outline-atomics','-I$work/deps/usr/include','-I$work/deps/usr/include/freetype2','-I$work/deps/usr/include/glib-2.0','-I$work/deps/usr/lib/glib-2.0/include']
c_link_args = ['-L$work/deps/usr/lib','-Wl,-rpath-link,$work/deps/usr/lib']
cpp_link_args = ['-L$work/deps/usr/lib','-Wl,-rpath-link,$work/deps/usr/lib']
EOF
echo 'HARFBUZZ_ICU_CONFIGURE=START'
if ! meson setup "$work/build" "$work/source" --cross-file "$work/cross.ini" \
 --prefix=/usr --libdir=lib --buildtype=release --wrap-mode=nodownload \
 -Ddefault_library=shared -Dicu=enabled -Dfreetype=enabled -Dglib=enabled \
 -Dcairo=enabled -Dgobject=disabled -Dgraphite=disabled -Dtests=disabled \
 -Ddocs=disabled -Dintrospection=disabled -Dutilities=disabled -Dbenchmark=disabled \
 > "$work/reports/configure.log" 2>&1; then
 echo 'HARFBUZZ_ICU_CONFIGURE=BLOCKED'; tail -n 100 "$work/reports/configure.log"; exit 10
fi
echo 'HARFBUZZ_ICU_CONFIGURE=PASS'
if ! meson compile -C "$work/build" -j 2 > "$work/reports/build.log" 2>&1; then
 echo 'HARFBUZZ_ICU_BUILD=BLOCKED'; tail -n 100 "$work/reports/build.log"; exit 11
fi
echo 'HARFBUZZ_ICU_BUILD=PASS'
if ! DESTDIR="$work/stage" meson install -C "$work/build" --no-rebuild > "$work/reports/install.log" 2>&1; then
 echo 'HARFBUZZ_ICU_INSTALL=BLOCKED'; tail -n 100 "$work/reports/install.log"; exit 12
fi
export PKG_CONFIG_LIBDIR="$work/stage/usr/lib/pkgconfig:$work/deps/usr/lib/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$work/stage"
for pc in harfbuzz harfbuzz-icu; do
 [[ $(pkg-config --modversion "$pc") == 11.2.1 ]] || { echo "ERROR: $pc metadata missing"; exit 13; }
done
for lib in libharfbuzz.so.0 libharfbuzz-icu.so.0; do
 file="$work/stage/usr/lib/$lib"
 test -s "$file"
 readelf -h "$file" | grep -Eq 'Machine:.*AArch64'
 readelf -d "$file" > "$work/reports/$lib.dynamic.txt"
 readelf -V "$file" > "$work/reports/$lib.versions.txt"
 if grep -Eq 'TEXTREL|Shared library: \[libgst' "$work/reports/$lib.dynamic.txt"; then exit 13; fi
done
grep -Fq 'Shared library: [libicuuc.so.74]' "$work/reports/libharfbuzz-icu.so.0.dynamic.txt"
python3 - "$work/reports" <<'PY'
from pathlib import Path
import re,sys
for f in Path(sys.argv[1]).glob("*.versions.txt"):
 v=[tuple(map(int,x.split("."))) for x in re.findall(r"Name: GLIBC_([0-9.]+)",f.read_text())]
 assert all(x<=(2,41) for x in v),(f,v)
print("HARFBUZZ_ICU_GLIBC=PASS_MAX_2_41")
PY
cat > "$work/hb-probe.c" <<'C'
#include <hb.h>
#include <hb-icu.h>
int fire4nix_hb_icu_probe(void) {
 hb_unicode_funcs_t *uf=hb_icu_get_unicode_funcs();
 hb_buffer_t *buffer=hb_buffer_create();
 hb_buffer_add_utf8(buffer,"R36H",4,0,-1);
 hb_buffer_guess_segment_properties(buffer);
 hb_buffer_destroy(buffer);
 return uf != 0;
}
C
"$cc" -mcpu=cortex-a35 -mno-outline-atomics -O2 -fPIC -shared -Wl,-z,defs \
 -I"$work/stage/usr/include/harfbuzz" "$work/hb-probe.c" \
 -L"$work/stage/usr/lib" -L"$work/deps/usr/lib" \
 -Wl,-rpath-link,"$work/deps/usr/lib" \
 -lharfbuzz-icu -lharfbuzz -licuuc -o "$work/libhb-icu-probe.so"
readelf -h "$work/libhb-icu-probe.so" | grep -Eq 'Machine:.*AArch64'
{
 echo 'HARFBUZZ_ICU=PASS_REAL_ROCKNIX_AARCH64'
 echo 'HARFBUZZ_VERSION=11.2.1'
 echo 'ICU_VERSION=74.1'
 echo 'ICU_COMPONENT=ENABLED'
 echo 'HARFBUZZ_ICU_PC=PASS'
 echo 'WEBKIT_BUILT=no'
 echo 'TARGET_EXECUTED=no'
 echo 'R36H_INSTALLABLE=no'
} | tee "$work/reports/result.txt"
cat "$work/reports/result.txt" >> "$GITHUB_STEP_SUMMARY"
