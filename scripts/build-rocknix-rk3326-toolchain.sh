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
# Preserve the other agent's verified source mirror; change only its URL in the
# disposable checkout. Upstream still verifies the original package digest.
FIRE4NIX_7ZIP_REPORT="$report/7zip-mirror.txt" \
  bash "$repo/scripts/verify-rocknix-7zip-mirror.sh" --check
python3 - "$root" "$report" <<'PY'
import pathlib, sys
root, report = map(pathlib.Path, sys.argv[1:])
fields = dict(line.split('=', 1) for line in (report / '7zip-mirror.txt').read_text().splitlines() if '=' in line)
assert fields.get('SOURCE_MIRROR_STATUS') == 'PASS'
url = fields['MIRROR_VERIFIED']
assert url in (
    'https://downloads.sourceforge.net/project/sevenzip/7-Zip/25.00/7z2500-src.tar.xz',
    'https://sourceforge.net/projects/sevenzip/files/7-Zip/25.00/7z2500-src.tar.xz/download',
    'https://master.dl.sourceforge.net/project/sevenzip/7-Zip/25.00/7z2500-src.tar.xz',
)
recipe = root / 'packages/compress/7-zip/package.mk'
source = recipe.read_text()
assert 'PKG_VERSION="25.00"' in source
assert 'PKG_SHA256="' + fields['VERIFIED_SHA256'] + '"' in source
old = 'PKG_URL="https://www.7-zip.org/a/7z${PKG_VERSION/./}-src.tar.xz"'
assert source.count(old) == 1
recipe.write_text(source.replace(old, 'PKG_URL="' + url + '"'))
PY
git -C "$root" diff -- packages/compress/7-zip/package.mk > "$report/7zip-url-only.patch"
# The original Savannah configtools archive URL and upstream distribution-sources
# mirror are both unavailable (HTTP 404 in run 39512765216). This independent
# source guard verifies the original SHA256 before changing ONLY the URL in
# the disposable checkout. Fail closed; never relax hash or use a new commit.
FIRE4NIX_CONFIGTOOLS_REPORT="$report/configtools-mirror.txt" \
  bash "$repo/scripts/verify-rocknix-configtools-source.sh" --check
FIRE4NIX_CONFIGTOOLS_REPORT="$report/configtools-mirror.txt" \
FIRE4NIX_ROCKNIX_SOURCE="$root" \
  bash "$repo/rocknix-integration/stage-configtools-source-mirror.sh" --check
FIRE4NIX_CONFIGTOOLS_REPORT="$report/configtools-mirror.txt" \
FIRE4NIX_ROCKNIX_SOURCE="$root" \
  bash "$repo/rocknix-integration/stage-configtools-source-mirror.sh" --apply
git -C "$root" diff --check
git -C "$root" diff -- packages/devel/configtools/package.mk > "$report/configtools-url-only.patch"
# The long compiler bootstrap reached XMLStarlet after compiling earlier host
# packages, but upstream HTTP mirror failed and distribution-sources gave 404.
# Repair only its URL after verifying the original archive checksum. Do not
# change version, SHA, platform, host dependencies or target dependencies.
FIRE4NIX_XMLSTARLET_REPORT="$report/xmlstarlet-mirror.txt" \
  bash "$repo/scripts/verify-rocknix-xmlstarlet-source.sh" --check
FIRE4NIX_XMLSTARLET_REPORT="$report/xmlstarlet-mirror.txt" \
FIRE4NIX_ROCKNIX_SOURCE="$root" \
  bash "$repo/rocknix-integration/stage-xmlstarlet-source-mirror.sh" --check
FIRE4NIX_XMLSTARLET_REPORT="$report/xmlstarlet-mirror.txt" \
FIRE4NIX_ROCKNIX_SOURCE="$root" \
  bash "$repo/rocknix-integration/stage-xmlstarlet-source-mirror.sh" --apply
git -C "$root" diff --check
git -C "$root" diff -- packages/textproc/xmlstarlet/package.mk > "$report/xmlstarlet-url-only.patch"
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
