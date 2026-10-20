#!/bin/sh
# Validate a REAL cross compiler with small disposable C and C++ executables.
# Does not run target ELF or touch the console, installed firmware or WPE.
set -eu
case "${1:---check}" in
  --check) ;;
  --help) echo 'Usage: FIRE4NIX_ROCKNIX_TOOLCHAIN=... FIRE4NIX_ROCKNIX_SYSROOT=... sh check-rocknix-compiler.sh --check'; exit 0 ;;
  *) echo 'Usage: check-rocknix-compiler.sh [--check|--help]' >&2; exit 2 ;;
esac
dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 2
toolchain=${FIRE4NIX_ROCKNIX_TOOLCHAIN:-}
sysroot=${FIRE4NIX_ROCKNIX_SYSROOT:-}
[ -n "$toolchain" ] && [ -f "$toolchain" ] || {
  echo 'ERROR: FIRE4NIX_ROCKNIX_TOOLCHAIN must be a CMake toolchain file' >&2; exit 4;
}
case "$sysroot" in
  /*) [ -d "$sysroot" ] || { echo 'ERROR: sysroot directory missing' >&2; exit 4; } ;;
  *) echo 'ERROR: FIRE4NIX_ROCKNIX_SYSROOT must be an absolute directory' >&2; exit 4 ;;
esac
command -v cmake >/dev/null 2>&1 && command -v ninja >/dev/null 2>&1 && command -v readelf >/dev/null 2>&1 || {
  echo 'ERROR: host requires cmake, ninja and readelf for compiler probe' >&2; exit 4;
}
# Run the lightweight identity check first; it catches obvious host sysroots.
sh "$dir/check-rocknix-sdk.sh" --check || exit 4
root=$(CDPATH= cd -- "$sysroot" && pwd -P) || exit 4
[ "$root" != / ] || { echo 'ERROR: host / is not an SDK sysroot' >&2; exit 4; }
tool_dir=$(CDPATH= cd -- "$(dirname -- "$toolchain")" && pwd -P)
toolchain="$tool_dir/$(basename -- "$toolchain")"
tmp=${TMPDIR:-/tmp}
work=$(mktemp -d "$tmp/fire4nix-wpe-compiler-XXXXXXXX") || exit 4
cleanup() { rm -rf "$work"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$work/source" "$work/build"
cat > "$work/source/CMakeLists.txt" <<'CMAKE'
cmake_minimum_required(VERSION 3.20)
project(Fire4NixCrossCompilerProbe LANGUAGES C CXX)
# This script receives the *actual resolved* CMAKE_SYSROOT used by the compiler,
# unlike parsing toolchain source or assuming it uses the declared SDK.
if(NOT CMAKE_SYSROOT)
  message(FATAL_ERROR "TARGET_CHECK: CMAKE_SYSROOT not set by the toolchain")
endif()
file(REAL_PATH "$ENV{FIRE4NIX_ROCKNIX_SYSROOT}" expected)
file(REAL_PATH "${CMAKE_SYSROOT}" actual)
if(NOT actual STREQUAL expected)
  message(FATAL_ERROR "TARGET_CHECK: compiler sysroot differs from declared ROCKNIX SDK")
endif()
string(TOLOWER "${CMAKE_SYSTEM_PROCESSOR}" machine)
if(NOT machine MATCHES "^(aarch64|arm64)$")
  message(FATAL_ERROR "TARGET_CHECK: compiler processor must be AArch64")
endif()
add_executable(fire4nix-c-probe main.c)
add_executable(fire4nix-cxx-probe main.cpp)
CMAKE
cat > "$work/source/main.c" <<'C'
#include <stdio.h>
int main(void) { return puts("fire4nix") < 0; }
C
cat > "$work/source/main.cpp" <<'CXX'
#include <string>
int main() { return std::string("fire4nix").size() != 8; }
CXX
# No explicit -DCMAKE_SYSROOT: do not silently repair a bad toolchain.
# Use the original toolchain settings as production WPE would.
FIRE4NIX_ROCKNIX_SYSROOT="$root" cmake -S "$work/source" -B "$work/build" -G Ninja \
  "-DCMAKE_TOOLCHAIN_FILE=$toolchain" \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_TRY_COMPILE_TARGET_TYPE=EXECUTABLE
cmake --build "$work/build" --parallel 2
for executable in "$work/build/fire4nix-c-probe" "$work/build/fire4nix-cxx-probe"; do
  [ -s "$executable" ] || { echo 'ERROR: compiler probe executable missing' >&2; exit 5; }
  if ! readelf -h "$executable" 2>/dev/null | grep -Eq 'Machine:.*AArch64'; then
    echo "ERROR: compiler produced a non-AArch64 executable: $executable" >&2; exit 5
  fi
  # The runtime may not define every transitive dependency; this caps the
  # libc symbol requirements of the two compiler-generated executables only.
  needed=$(readelf -V "$executable" 2>/dev/null | grep -oE 'Name: GLIBC_[0-9]+\.[0-9]+' | sed 's/Name: GLIBC_//' | sort -Vu | tail -n 1 || true)
  max=2.41
  [ "${FIRE4NIX_ROCKNIX_RELEASE:-20260801}" != 20261001 ] || max=2.44
  if [ -n "$needed" ] && ! awk -v req="$needed" -v max="$max" 'BEGIN {
    split(req,a,"."); split(max,b,".");
    exit !(a[1] < b[1] || (a[1]==b[1] && a[2]<=b[2]))
  }'; then
    echo "ERROR: probe requires GLIBC_$needed newer than target GLIBC_$max" >&2; exit 5
  fi
done
echo 'COMPILER_PREFLIGHT=PASS'
echo "sysroot=$root"
echo 'abi=AArch64'
echo 'probes=C,CXX'
echo 'target_executed=no'
echo 'note=does_not_prove_transitive_webkit_dependencies_or_actual_gpu_rendering'
