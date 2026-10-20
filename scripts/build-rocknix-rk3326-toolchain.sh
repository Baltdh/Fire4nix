#!/usr/bin/env bash
# Build-host only: genuine ROCKNIX cross-toolchain, never a firmware image.
set -euo pipefail
repo=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
root=${FIRE4NIX_ROCKNIX_SOURCE:?Set disposable ROCKNIX source checkout}
root=$(cd -- "$root" && pwd -P)
[[ ${GITHUB_ACTIONS:-} == true && $(id -u) != 0 ]] || {
  echo 'ERROR: this bootstrap is restricted to a non-root GitHub runner'; exit 4;
}
case "$root" in
  "$GITHUB_WORKSPACE"/rocknix-source) ;;
  *) echo 'ERROR: expected isolated rocknix-source in GITHUB_WORKSPACE'; exit 4 ;;
esac
expected=3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb
[[ $(git -C "$root" rev-parse HEAD) == "$expected" ]] || {
  echo 'ERROR: source commit mismatch'; exit 4;
}
grep -Fxq 'PKG_VERSION="2.41"' "$root/projects/ROCKNIX/packages/devel/glibc/package.mk"
export PROJECT=ROCKNIX DEVICE=RK3326 ARCH=aarch64
export FIRE4NIX_ROCKNIX_SOURCE="$root"
report="$GITHUB_WORKSPACE/toolchain-reports"
mkdir -p "$report"
printf 'ROCKNIX_SOURCE=%s\nDEVICE=RK3326\nWEBKIT_BUILT=no\n' "$expected" > "$report/status.txt"
sh "$repo/rocknix-integration/audit-rocknix-rk3326-source.sh" --check > "$report/source-audit.txt"
cd "$root"
# Use upstream dependency resolution and the project GCC/glibc overrides.
# No scripts/image, install, build_distro, flashing or target execution.
./scripts/checkdeps </dev/null
./scripts/build toolchain 2>&1 | tee "$report/toolchain-build.log"
sdk="$root/build.ROCKNIX-RK3326.aarch64/toolchain"
sysroot="$sdk/aarch64-rocknix-linux-gnu/sysroot"
cc="$sdk/bin/aarch64-rocknix-linux-gnu-gcc"
cxx="$sdk/bin/aarch64-rocknix-linux-gnu-g++"
[[ -x "$cc" && -x "$cxx" && -d "$sysroot" ]] || {
  echo 'ERROR: upstream did not produce the expected cross compiler/sysroot'; exit 5;
}
"$cc" --version > "$report/compiler-version.txt"
"$cc" -dumpmachine > "$report/compiler-target.txt"
cat > "$sdk/fire4nix-toolchain.cmake" <<EOF
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
set(CMAKE_SYSROOT "$sysroot")
set(CMAKE_C_COMPILER "$cc")
set(CMAKE_CXX_COMPILER "$cxx")
set(CMAKE_C_FLAGS_INIT "-mcpu=cortex-a35+crc+fp+simd")
set(CMAKE_CXX_FLAGS_INIT "-mcpu=cortex-a35+crc+fp+simd")
set(CMAKE_FIND_ROOT_PATH "$sysroot")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
EOF
FIRE4NIX_ROCKNIX_TOOLCHAIN="$sdk/fire4nix-toolchain.cmake" \
FIRE4NIX_ROCKNIX_SYSROOT="$sysroot" \
  sh "$repo/rocknix-integration/check-rocknix-compiler.sh" --check \
  2>&1 | tee "$report/compiler-probe.txt"
printf 'TOOLCHAIN_BUILD=PASS\nREAL_C_CXX_PROBE=PASS\nWEBKIT_BUILT=no\nDEVICE_TESTED=no\n' >> "$report/status.txt"
# Host build checkpoint, not an installation package; paths remain runner-specific.
tar -C "$root/build.ROCKNIX-RK3326.aarch64" -cJf "$GITHUB_WORKSPACE/rocknix-toolchain-host-only.tar.xz" toolchain
