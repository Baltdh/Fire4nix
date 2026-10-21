#!/usr/bin/env bash
# First genuine library built with the ROCKNIX 20260801 RK3326 cross compiler.
# Build-host only; no target execution, firmware writes, or library installs.
set -euo pipefail
mode=${1:---build}
case "$mode" in --build) ;; --help)
  echo 'Usage: FIRE4NIX_ROCKNIX_TOOLCHAIN_ROOT=/absolute/toolchain FIRE4NIX_LIBTASN1_WORK=/tmp/... bash build-rocknix-libtasn1.sh --build'; exit 0 ;;
  *) echo 'ERROR: --build or --help only' >&2; exit 2 ;;
esac
script_dir=$(cd -- "$(dirname -- "$0")" && pwd -P)
repo=$(cd -- "$script_dir/.." && pwd -P)
[[ "${GITHUB_ACTIONS:-}" == true && "$(id -u)" != 0 && -n "${GITHUB_WORKSPACE:-}" ]] || {
  echo 'ERROR: CI runner only; never build on device' >&2; exit 4;
}
toolchain=${FIRE4NIX_ROCKNIX_TOOLCHAIN_ROOT:-}
[[ "$toolchain" == /* && -d "$toolchain" ]] || { echo 'ERROR: absolute ROCKNIX toolchain directory required' >&2; exit 4; }
toolchain=$(cd -- "$toolchain" && pwd -P)
[[ "$toolchain" == "$GITHUB_WORKSPACE/rocknix-source/build.ROCKNIX-RK3326.aarch64/toolchain" ]] || {
  echo 'ERROR: expected pinned host-only toolchain at original runner workspace path' >&2; exit 4;
}
sysroot="$toolchain/aarch64-rocknix-linux-gnu/sysroot"
cc="$toolchain/bin/aarch64-rocknix-linux-gnu-gcc"
cxx="$toolchain/bin/aarch64-rocknix-linux-gnu-g++"
ar="$toolchain/bin/aarch64-rocknix-linux-gnu-ar"
ranlib="$toolchain/bin/aarch64-rocknix-linux-gnu-ranlib"
cmake_toolchain="$toolchain/fire4nix-toolchain.cmake"
[[ -x "$cc" && -x "$cxx" && -x "$ar" && -x "$ranlib" && -f "$cmake_toolchain" ]] || {
  echo 'ERROR: compiler, binutils, or CMake toolchain file missing from checkpoint' >&2; exit 4;
}
[[ "$("$cc" -dumpmachine)" == 'aarch64-rocknix-linux-gnu' ]] || { echo 'ERROR: wrong compiler target' >&2; exit 4; }
work=${FIRE4NIX_LIBTASN1_WORK:-"$GITHUB_WORKSPACE/libtasn1-rocknix-work"}
case "$work" in "$GITHUB_WORKSPACE"/*) ;; *) echo 'ERROR: isolated CI work directory required' >&2; exit 4 ;; esac
[[ ! -e "$work" ]] || { echo 'ERROR: refusing to overwrite existing workdir' >&2; exit 4; }
mkdir -p "$work"/{source,build,stage,reports}
report="$work/reports"
{
  echo 'ROCKNIX_SOURCE=20260801'
  echo 'ROCKNIX_DEVICE=RK3326'
  echo 'TARGET_MACHINE=aarch64-rocknix-linux-gnu'
  echo 'TARGET_MAX_GLIBC=2.41'
  echo 'LIBTASN1_VERSION=4.21.0'
  echo 'LIBTASN1_SOURCE_SHA256=1d8a444a223cc5464240777346e125de51d8e6abf0b8bac742ac84609167dc87'
  echo 'BUILD_STATUS=STARTED'
  echo 'R36H_INSTALLABLE=no'
} > "$report/status.txt"
FIRE4NIX_ROCKNIX_TOOLCHAIN="$cmake_toolchain" FIRE4NIX_ROCKNIX_SYSROOT="$sysroot" \
  sh "$repo/rocknix-integration/check-rocknix-sdk.sh" --check > "$report/sdk-check.txt"
FIRE4NIX_ROCKNIX_TOOLCHAIN="$cmake_toolchain" FIRE4NIX_ROCKNIX_SYSROOT="$sysroot" \
  sh "$repo/rocknix-integration/check-rocknix-compiler.sh" --check > "$report/compiler-probe.txt"
version=4.21.0
sha=1d8a444a223cc5464240777346e125de51d8e6abf0b8bac742ac84609167dc87
url="https://ftp.gnu.org/gnu/libtasn1/libtasn1-$version.tar.gz"
archive="$work/source/libtasn1-$version.tar.gz"
curl --fail --location --silent --show-error --retry 2 --retry-delay 2 \
  --proto '=https' --proto-redir '=https' --connect-timeout 15 --max-time 180 \
  --output "$archive" "$url"
echo "$sha  $archive" | sha256sum --check
tar -tzf "$archive" > "$report/archive-contents.txt"
grep -Eq '^libtasn1-4\.21\.0/configure$' "$report/archive-contents.txt"
tar -xzf "$archive" -C "$work/source"
echo "LIBTASN1_ARCHIVE=PASS_UPSTREAM_SHA256_$sha" > "$report/source.txt"
cd "$work/build"
CC="$cc" CXX="$cxx" AR="$ar" RANLIB="$ranlib" \
 CFLAGS='-O2 -mcpu=cortex-a35 -fPIC' \
 "$work/source/libtasn1-$version/configure" \
  --build="$(gcc -dumpmachine)" \
  --host=aarch64-rocknix-linux-gnu \
  --prefix=/usr --libdir=/usr/lib \
  --disable-static --enable-shared \
  --disable-dependency-tracking \
  > "$report/configure.log" 2>&1
make --jobs=2 > "$report/build.log" 2>&1
make DESTDIR="$work/stage" install > "$report/install.log" 2>&1
lib="$work/stage/usr/lib/libtasn1.so.6"
[[ -s "$lib" ]] || { echo 'ERROR: missing libtasn1.so.6 SONAME' >&2; exit 6; }
readelf -h "$lib" > "$report/elf-header.txt"
readelf -d "$lib" > "$report/elf-needed.txt"
readelf -V "$lib" > "$report/elf-versions.txt"
grep -Eq 'Class:.*ELF64' "$report/elf-header.txt"
grep -Eq 'Machine:.*AArch64' "$report/elf-header.txt"
grep -Eq 'Type:.*DYN' "$report/elf-header.txt"
if grep -Eq 'Shared library: \[libgst[^]]*\]' "$report/elf-needed.txt"; then
 echo 'ERROR: unexpectedly linked GStreamer in libtasn1' >&2; exit 6
fi
required=$(grep -oE 'Name: GLIBC_[0-9]+\.[0-9]+' "$report/elf-versions.txt" \
  | sed 's/Name: GLIBC_//' | sort -Vu | tail -n 1 || true)
if [[ -n "$required" ]] && ! awk -v req="$required" 'BEGIN { split(req,a,"."); exit !(a[1]<2 || (a[1]==2 && a[2]<=41)) }'; then
  echo "ERROR: libtasn1 requires newer GLIBC_$required" >&2; exit 6
fi
pc="$work/stage/usr/lib/pkgconfig/libtasn1.pc"
[[ -s "$pc" ]] || { echo 'ERROR: target pkg-config metadata missing' >&2; exit 6; }
PKG_CONFIG_LIBDIR="$work/stage/usr/lib/pkgconfig" PKG_CONFIG_SYSROOT_DIR="$work/stage" \
  PKG_CONFIG_PATH='' pkg-config --exists 'libtasn1 >= 4.21.0'
[[ -s "$work/stage/usr/include/libtasn1.h" ]] || {
  echo 'ERROR: target libtasn1.h development header missing' >&2; exit 6;
}
# Compile and link a target AArch64 consumer against newly staged libtasn1.
# This does not execute target code on the Ubuntu build host.
cat > "$work/build/libtasn1-consumer.c" <<'CONSUMER'
#include <libtasn1.h>
int main(void) { return asn1_check_version(0) ? 0 : 1; }
CONSUMER
"$cc" -O2 -mcpu=cortex-a35 \
  -I"$work/stage/usr/include" \
  -L"$work/stage/usr/lib" \
  -Wl,-rpath-link,"$work/stage/usr/lib" \
  -o "$work/build/libtasn1-consumer-aarch64" \
  "$work/build/libtasn1-consumer.c" -ltasn1
readelf -h "$work/build/libtasn1-consumer-aarch64" > "$report/consumer-elf-header.txt"
readelf -d "$work/build/libtasn1-consumer-aarch64" > "$report/consumer-elf-needed.txt"
grep -Eq 'Machine:.*AArch64' "$report/consumer-elf-header.txt"
grep -Eq 'Shared library: \[libtasn1.so.6\]' "$report/consumer-elf-needed.txt"
required_consumer=$(readelf -V "$work/build/libtasn1-consumer-aarch64" 2>/dev/null \
  | grep -oE 'Name: GLIBC_[0-9]+\.[0-9]+' | sed 's/Name: GLIBC_//' \
  | sort -Vu | tail -n 1 || true)
if [[ -n "$required_consumer" ]] && ! awk -v req="$required_consumer" 'BEGIN { split(req,a,"."); exit !(a[1]<2 || (a[1]==2 && a[2]<=41)) }'; then
 echo "ERROR: linked consumer requires newer GLIBC_$required_consumer" >&2; exit 6
fi
echo 'LIBTASN1_CONSUMER_LINK=PASS_AARCH64_TARGET_AND_SONAME' > "$report/consumer-link.txt"
{
 echo 'LIBTASN1_BUILD=PASS_REAL_ROCKNIX_CROSS_COMPILE'
 echo 'LIBTASN1_TARGET=ELF64_AARCH64'
 echo "LIBTASN1_MAX_REQUIRED_GLIBC=${required:-NONE}"
 echo 'LIBTASN1_CONSUMER_LINK=PASS_AARCH64_TARGET_AND_SONAME'
 echo 'LIBTASN1_DEV_PC=PASS'
 echo 'LIBTASN1_HEADERS=PASS'
 echo 'LIBTASN1_TARGET_EXECUTED=no'
 echo 'WPE_WEBKIT_BUILT=no'
 echo 'R36H_TESTED=no'
} >> "$report/status.txt"
(cd "$work/stage" && find . -type f -print0 | sort -z | xargs -0 sha256sum) > "$report/staged-sha256sums.txt"
tar -C "$work/stage" -cJf "$GITHUB_WORKSPACE/libtasn1-4.21.0-ROCKNIX-RK3326-CROSS-STAGE-ONLY.tar.xz" .
echo 'LIBTASN1_SMOKE=PASS_REAL_CROSS_COMPILATION_NOT_BROWSER'
