#!/usr/bin/env bash
# Genuine ICU 74.1 HOST tools + ROCKNIX RK3326 AArch64 target libs.
# No target ELF execution; no console writes.
set -euo pipefail
[[ ${GITHUB_ACTIONS:-} == true && $(id -u) != 0 && -n ${GITHUB_WORKSPACE:-} ]] || { echo 'ERROR: non-root GitHub CI only'; exit 4; }
root="$GITHUB_WORKSPACE"
repo="$root/rocknix-source"
sdk="$repo/build.ROCKNIX-RK3326.aarch64/toolchain"
work="$root/icu74-target"
[[ ! -e "$work" && ! -L "$work" ]] || { echo 'ERROR: refusing overwrite'; exit 4; }
mkdir -p "$work"/{source,host,build,stage,reports}
[[ $(git -C "$repo" rev-parse HEAD) == 3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb ]]
recipe="$repo/projects/ROCKNIX/packages/textproc/icu/package.mk"
grep -Fxq 'PKG_VERSION="74.1"' "$recipe"
cc="$sdk/bin/aarch64-rocknix-linux-gnu-gcc"
cxx="$sdk/bin/aarch64-rocknix-linux-gnu-g++"
[[ $("$cc" -dumpmachine) == aarch64-rocknix-linux-gnu ]]
echo 'ICU74_SOURCE_DOWNLOAD=START'
curl -fLsS --retry 2 --connect-timeout 20 --max-time 180 \
 --proto '=https' --proto-redir '=https' \
 'https://github.com/unicode-org/icu/releases/download/release-74-1/icu4c-74_1-src.tgz' \
 -o "$work/icu4c-74_1-src.tgz"
# Verify the official ICU74.1 archive against a published independent checksum,
# not a hash learned from the archive we just downloaded.
printf '%s\n' '71e60b22697c4f35820a1897417dbab4  '"$work/icu4c-74_1-src.tgz" | md5sum --check
sha256sum "$work/icu4c-74_1-src.tgz" | tee "$work/reports/source-sha256.txt"
tar -xzf "$work/icu4c-74_1-src.tgz" -C "$work/source"
src="$work/source/icu/source"
test -x "$src/configure"
# ICU cross builds require a runnable HOST ICU build to generate target data.
echo 'ICU74_HOST_CONFIGURE=START'
(
cd "$work/host"
"$src/configure" --prefix="$work/host/install" --disable-layout --disable-layoutex \
 --enable-renaming --disable-samples --disable-tests --enable-tools --disable-extras \
 > "$work/reports/host-configure.log" 2>&1
) || { echo 'ICU74_HOST_CONFIGURE=BLOCKED'; tail -n 85 "$work/reports/host-configure.log"; exit 10; }
echo 'ICU74_HOST_BUILD=START'
make -C "$work/host" -j 2 > "$work/reports/host-build.log" 2>&1 || {
 echo 'ICU74_HOST_BUILD=BLOCKED'; tail -n 110 "$work/reports/host-build.log"; exit 11; }
echo 'ICU74_HOST_BUILD=PASS'
echo 'ICU74_TARGET_CONFIGURE=START'
(
cd "$work/build"
CC="$cc" CXX="$cxx" AR="$sdk/bin/aarch64-rocknix-linux-gnu-ar" \
 RANLIB="$sdk/bin/aarch64-rocknix-linux-gnu-ranlib" \
 STRIP="$sdk/bin/aarch64-rocknix-linux-gnu-strip" \
 CFLAGS='-O2 -fPIC -mcpu=cortex-a35' CXXFLAGS='-O2 -fPIC -mcpu=cortex-a35' \
 "$src/configure" --host=aarch64-rocknix-linux-gnu --prefix=/usr --libdir=/usr/lib \
 --disable-layout --disable-layoutex --enable-renaming \
 --disable-samples --disable-tests --disable-tools --disable-extras \
 --with-cross-build="$work/host" > "$work/reports/target-configure.log" 2>&1
) || { echo 'ICU74_TARGET_CONFIGURE=BLOCKED'; tail -n 110 "$work/reports/target-configure.log"; exit 12; }
echo 'ICU74_TARGET_CONFIGURE=PASS'
make -C "$work/build" -j 2 > "$work/reports/target-build.log" 2>&1 || {
 echo 'ICU74_TARGET_BUILD=BLOCKED'; tail -n 115 "$work/reports/target-build.log"; exit 13; }
echo 'ICU74_TARGET_BUILD=PASS'
make -C "$work/build" DESTDIR="$work/stage" install > "$work/reports/target-install.log" 2>&1 || {
 echo 'ICU74_TARGET_INSTALL=BLOCKED'; tail -n 105 "$work/reports/target-install.log"; exit 14; }
for soname in libicuuc.so.74 libicui18n.so.74 libicudata.so.74; do
 file="$work/stage/usr/lib/$soname"
 if ! test -s "$file"; then
   file=$(find "$work/stage/usr/lib" -maxdepth 1 -type f -name "$soname*" -print -quit)
 fi
 test -n "$file" && test -s "$file" || { echo "ERROR: absent ICU target $soname"; exit 15; }
 readelf -h "$file" | grep -Eq 'Machine:.*AArch64' || { echo "ERROR: wrong ELF machine $file"; exit 15; }
 readelf -d "$file" > "$work/reports/$soname.dynamic.txt"
 readelf -V "$file" > "$work/reports/$soname.versions.txt"
 if grep -Eq 'TEXTREL|Shared library: \[libgst' "$work/reports/$soname.dynamic.txt"; then exit 15; fi
done
python3 - "$work/reports" <<'PY'
import pathlib,re,sys
for f in pathlib.Path(sys.argv[1]).glob('*.versions.txt'):
 vs=[tuple(map(int,x.split('.'))) for x in re.findall(r'Name: GLIBC_([0-9.]+)',f.read_text())]
 assert all(v <= (2,41) for v in vs),(f,vs)
print('ICU74_GLIBC=PASS_MAX_2_41')
PY
# Generate a real cross-linked consumer. Do not execute AArch64 output on host.
cat > "$work/icu-consumer.cpp" <<'CPP'
#include <unicode/unistr.h>
#include <unicode/numfmt.h>
#include <unicode/ucnv.h>
#include <unicode/uversion.h>
extern "C" int fire4nix_icu74_probe() {
 UErrorCode status=U_ZERO_ERROR;
 icu::UnicodeString s=icu::UnicodeString::fromUTF8("R36H Fire4Nix");
 icu::NumberFormat *fmt=icu::NumberFormat::createInstance(status);
 if (fmt) delete fmt;
 UVersionInfo version = {0, 0, 0, 0};
 u_getVersion(version);
 return s.length() > 0 && U_SUCCESS(status) && ucnv_countAvailable() > 0 && version[0] == 74;
}
CPP
"$cxx" -O2 -mcpu=cortex-a35 -fPIC -shared -Wl,-z,defs \
 -I"$work/stage/usr/include" "$work/icu-consumer.cpp" \
 -L"$work/stage/usr/lib" -Wl,-rpath-link,"$work/stage/usr/lib" \
 -licui18n -licuuc -licudata -o "$work/libfire4nix-icu74-probe.so"
readelf -h "$work/libfire4nix-icu74-probe.so" | grep -Eq 'Machine:.*AArch64'
readelf -d "$work/libfire4nix-icu74-probe.so" > "$work/reports/consumer-dynamic.txt"
for soname in libicuuc.so.74 libicui18n.so.74; do
 grep -Fq "Shared library: [$soname]" "$work/reports/consumer-dynamic.txt"
done
{
 echo 'ICU74_BUILD=PASS_REAL_ROCKNIX_AARCH64'
 echo 'ICU_VERSION=74.1'
 echo 'ICU_COMPONENTS=uc,i18n,data'
 echo 'HOST_GENERATORS=BUILT_AND_RUN_ON_HOST_ONLY'
 echo 'TARGET_ELF_EXECUTED=no'
 echo 'WEBKIT_BUILT=no'
 echo 'R36H_INSTALLABLE=no'
} | tee "$work/reports/result.txt"
cat "$work/reports/result.txt" >> "$GITHUB_STEP_SUMMARY"
