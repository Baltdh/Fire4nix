#!/usr/bin/env bash
# Compile REAL WPEPlatform core + Wayland + headless object targets from WPE 2.54.1.
# These Ubuntu-native AArch64 objects are evidence of compilation, not R36H binaries.
set -euo pipefail
[ "$(uname -m)" = aarch64 ] || { echo 'ERROR: AArch64 native runner required' >&2; exit 4; }
work=${FIRE4NIX_BUILD_WORK:-}
[ -n "$work" ] && [ -f "$work/wpe-cmake/build.ninja" ] || {
  echo 'ERROR: configure WPE WebKit 2.54.1 first' >&2; exit 4
}
repo=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
report="$work/reports/WPEPLATFORM-REAL-ARM64-OBJECTS.txt"
mkdir -p "$work/reports"
FIRE4NIX_WPE_BUILD_DIR="$work/wpe-cmake" FIRE4NIX_MEDIA_PROFILE=minimal \
  sh "$repo/rocknix-integration/verify-wpe-media-cache.sh" --check
ninja -C "$work/wpe-cmake" -t targets all | grep -Eq '^WPEPlatform: phony$|^WPEPlatform:.*' || {
  echo 'ERROR: upstream WPEPlatform target missing' >&2; exit 5
}
for target in WPEPlatform WPEPlatformWayland WPEPlatformHeadless; do
  if ! ninja -C "$work/wpe-cmake" -t targets all | grep -Eq "^$target: phony$|^$target:"; then
    echo "ERROR: missing $target build target" >&2; exit 5
  fi
done
echo 'WPEPLATFORM_ARM64_BUILD=START'
if ! cmake --build "$work/wpe-cmake" \
  --target WPEPlatform WPEPlatformWayland WPEPlatformHeadless \
  --parallel "${FIRE4NIX_WPE_OBJECT_JOBS:-2}" \
  > "$work/reports/wpeplatform-build.log" 2>&1; then
  echo 'WPEPLATFORM_ARM64_BUILD=FAILED'
  tail -n 110 "$work/reports/wpeplatform-build.log"
  exit 10
fi
echo 'WPEPLATFORM_ARM64_BUILD=COMPLETED'
mapfile -t object_files < <(find "$work/wpe-cmake" -type f -name '*.o' | grep -E '/WPEPlatform(Headless|Wayland)?\.dir/' | sort)
test "${#object_files[@]}" -ge 20 || {
  echo "ERROR: only ${#object_files[@]} WPEPlatform objects, expected >= 20" >&2
  exit 10
}
core=0; wayland=0; headless=0
for object in "${object_files[@]}"; do
  if ! readelf -h "$object" | grep -Eq 'Machine:[[:space:]]+AArch64'; then
    echo "ERROR: not ELF AArch64: $object" >&2; exit 10
  fi
  case "$object" in
    */WPEPlatform.dir/*) core=$((core+1));;
    */WPEPlatformWayland.dir/*) wayland=$((wayland+1));;
    */WPEPlatformHeadless.dir/*) headless=$((headless+1));;
  esac
done
[ "$core" -ge 12 ] && [ "$wayland" -ge 1 ] && [ "$headless" -ge 1 ] || {
  echo "ERROR: incomplete targets core=$core wayland=$wayland headless=$headless" >&2
  exit 10
}
{
  echo 'WPEPLATFORM_OBJECT_TEST=PASS_REAL_AARCH64_OBJECTS'
  echo "CORE_OBJECTS=$core"
  echo "WAYLAND_OBJECTS=$wayland"
  echo "HEADLESS_OBJECTS=$headless"
  echo "TOTAL_OBJECTS=${#object_files[@]}"
  echo 'SOURCE=wpewebkit-2.54.1'
  echo 'GST_PROFILE=OFF_CONFIRMED_CMAKE_CACHE'
  echo 'UBUNTU_ARM64_BUILD=YES'
  echo 'ROCKNIX_SYSROOT_USED=NO'
  echo 'LINKED_WEBKIT_SO=NO'
  echo 'BROWSER_FUNCTIONAL=NO'
  echo 'DEVICE_FLASH_OR_STORAGE_CHANGED=NO'
} | tee "$report"
