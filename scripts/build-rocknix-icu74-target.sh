#!/usr/bin/env bash
# Compile ICU 74.1 for ROCKNIX RK3326 via native ICU cross-build tooling.
# Do not run ARM binaries or install on handheld; only isolated GitHub CI.
set -euo pipefail
[[ ${GITHUB_ACTIONS:-} == true && $(id -u) != 0 && -n ${GITHUB_WORKSPACE:-} ]] || exit 4
root="$GITHUB_WORKSPACE"
sdk="$root/rocknix-source/build.ROCKNIX-RK3326.aarch64/toolchain"
work="$root/icu74-target"
recipe="$root/rocknix-source/projects/ROCKNIX/packages/textproc/icu/package.mk"
[[ ! -e "$work" && ! -L "$work" ]] || { echo 'ERROR: output exists' >&2; exit 4; }
[[ $(git -C "$root/rocknix-source" rev-parse HEAD) == 3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb ]]
grep -Fxq 'PKG_VERSION="74.1"' "$recipe"
cc="$sdk/bin/aarch64-rocknix-linux-gnu-gcc"
cxx="$sdk/bin/aarch64-rocknix-linux-gnu-g++"
[[ $("$cc" -dumpmachine) == aarch64-rocknix-linux-gnu ]] || exit 4
for tool in curl sha256sum tar make gcc g++ readelf pkg-config; do command -v "$tool" >/dev/null || exit 4; done
mkdir -p "$work"/{source,host-build,target-build,stage,reports}
archive="$work/icu4c-74_1-src.tgz"
checksum=86ce8e60681972e60e4dcb2490c697463fcec60dd400a5f9bffba26d0b52b8d0
curl --proto '=https' --proto-redir '=https' -fLsS --retry 2 --max-time 210 \
  https://github.com/unicode-org/icu/releases/download/release-74-1/icu4c-74_1-src.tgz \
  -o "$archive"
echo "$checksum  $archive" | sha256sum --check
tar -xzf "$archive" -C "$work/source"
test -x "$work/source/icu/source/configure"
# ICU requires build-host copies of its data generation tools for cross builds.
# Keep host binaries isolated and ensure only AArch64 libraries enter the target stage.
echo 'ICU_HOST_CONFIGURE=START'
if ! (cd "$work/host-build" && "$work/source/icu/source/configure" \
  --prefix="$work/host-install" --disable-samples --disable-tests \
  --disable-extras --disable-layout --disable-layoutex \
  > "$work/reports/host-configure.log" 2>&1); then
  echo 'ICU_HOST_CONFIGURE=BLOCKED'; tail -n 90 "$work/reports/host-configure.log"; exit 10
fi
if ! make -C "$work/host-build" -j 2 > "$work/reports/host-build.log" 2>&1; then
  echo 'ICU_HOST_BUILD=BLOCKED'; tail -n 90 "$work/reports/host-build.log"; exit 11
fi
echo 'ICU_HOST_BUILD=PASS'
echo 'ICU_TARGET_CONFIGURE=START'
sysroot="$sdk/aarch64-rocknix-linux-gnu/sysroot"
if ! (cd "$work/target-build" && \
  CC="$cc" CXX="$cxx" AR="$sdk/bin/aarch64-rocknix-linux-gnu-ar" \
  RANLIB="$sdk/bin/aarch64-rocknix-linux-gnu-ranlib" \
  CFLAGS="-O2 -mcpu=cortex-a35 --sysroot=$sysroot" \
  CXXFLAGS="-O2 -mcpu=cortex-a35 --sysroot=$sysroot" \
  LDFLAGS="--sysroot=$sysroot" \
  "$work/source/icu/source/configure" \
  --host=aarch64-rocknix-linux-gnu --build="$(gcc -dumpmachine)" \
  --prefix=/usr --libdir=/usr/lib --disable-samples --disable-tests \
  --disable-extras --disable-layout --disable-layoutex \
  --with-cross-build="$work/host-build" \
  > "$work/reports/target-configure.log" 2>&1); then
  echo 'ICU_TARGET_CONFIGURE=BLOCKED'; tail -n 110 "$work/reports/target-configure.log"; exit 12
fi
echo 'ICU_TARGET_CONFIGURE=PASS'
if ! make -C "$work/target-build" -j 2 > "$work/reports/target-build.log" 2>&1; then
 echo 'ICU_TARGET_BUILD=BLOCKED'; tail -n 110 "$work/reports/target-build.log"; exit 13
fi
echo 'ICU_TARGET_BUILD=PASS'
if ! make -C "$work/target-build" DESTDIR="$work/stage" install \
   > "$work/reports/target-install.log" 2>&1; then
 echo 'ICU_TARGET_INSTALL=BLOCKED'; tail -n 100 "$work/reports/target-install.log"; exit 14
fi
for name in libicuuc.so.74 libicui18n.so.74 libicudata.so.74; do
 lib="$work/stage/usr/lib/$name"
 test -s "$lib" || { echo "ERROR: missing $name" >&2; exit 15; }
 readelf -h "$lib" | grep -Eq 'Machine:.*AArch64'
 readelf -V "$lib" > "$work/reports/$name.versions.txt"
 readelf -d "$lib" > "$work/reports/$name.dynamic.txt"
 if grep -Eq 'TEXTREL|Shared library: \[libgst' "$work/reports/$name.dynamic.txt"; then exit 15; fi
done
python3 - "$work/reports" <<'PY'
from pathlib import Path
import re,sys
for p in Path(sys.argv[1]).glob('*.versions.txt'):
 versions=[tuple(map(int,n.split('.'))) for n in re.findall(r'Name: GLIBC_([0-9.]+)',p.read_text())]
 if not all(v<=(2,41) for v in versions): raise SystemExit(f'ICU ABI incompatible: {p} {versions}')
print('ICU_GLIBC=PASS_MAX_2_41')
PY
export PKG_CONFIG_LIBDIR="$work/stage/usr/lib/pkgconfig" PKG_CONFIG_PATH='' PKG_CONFIG_SYSROOT_DIR="$work/stage"
for pkg in icu-uc icu-i18n; do
 version=$(pkg-config --modversion "$pkg") || { echo "ERROR: missing $pkg.pc" >&2; exit 16; }
 [[ $version == 74.1 ]] || { echo "ERROR: version mismatch $pkg=$version" >&2; exit 16; }
done
{
 echo 'ICU_TARGET=PASS_REAL_ROCKNIX_AARCH64'
 echo 'ICU_VERSION=74.1'
 echo 'ICU_COMPONENTS=uc,i18n,data'
 echo 'SOURCE_SHA256=VERIFIED_PINNED'
 echo 'HOST_TOOLS=BUILT_NATIVE_ONLY'
 echo 'TARGET_EXECUTED=no'
 echo 'WEBKIT_BUILT=no'
 echo 'R36H_INSTALLABLE=no'
} | tee "$work/reports/acceptance.txt"
cat "$work/reports/acceptance.txt" >> "$GITHUB_STEP_SUMMARY"
