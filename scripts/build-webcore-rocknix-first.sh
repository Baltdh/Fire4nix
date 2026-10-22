#!/usr/bin/env bash
# Compile genuine WebCore OBJECT target for ROCKNIX RK3326, if the pinned SDK
# successfully configures WPE. Does NOT build a complete runnable browser.
set -euo pipefail
[[ ${GITHUB_ACTIONS:-} == true && $(id -u) != 0 && -n ${GITHUB_WORKSPACE:-} ]] || {
  echo 'ERROR: non-root GitHub Actions runner required' >&2; exit 4;
}
base="$GITHUB_WORKSPACE"
dir="$base/wpe-unified-sdk-build"
build="$dir/configure"
report="$dir/report"
test -s "$build/build.ninja"
test -s "$build/CMakeCache.txt"
grep -Fxq 'WPE_CMAKE_EXIT_CODE=0' "$report/status.txt"
for entry in \
 'ENABLE_WPE_PLATFORM:BOOL=ON' \
 'ENABLE_WPE_PLATFORM_WAYLAND:BOOL=ON' \
 'USE_GSTREAMER:BOOL=OFF' \
 'USE_LIBDRM:BOOL=OFF' \
 'USE_GBM:BOOL=OFF'; do
 grep -Fxq "$entry" "$build/CMakeCache.txt" || {
  echo "ERROR: incorrect CMake option $entry" >&2; exit 5;
 }
done
sdk="$base/rocknix-source/build.ROCKNIX-RK3326.aarch64/toolchain"
test "$("$sdk/bin/aarch64-rocknix-linux-gnu-gcc" -dumpmachine)" = aarch64-rocknix-linux-gnu
# WebCore is an OBJECT target in upstream WebKit; check Ninja target first.
if ! ninja -C "$build" -t targets all | awk -F: '$1=="WebCore" {found=1} END {exit !found}'; then
 echo 'WEBCORE_TARGET=NOT_FOUND'
 ninja -C "$build" -t targets all | grep -i webcore | head -n 35 || true
 exit 6
fi
echo 'WEBCORE_ROCKNIX_TARGET_BUILD=START' | tee "$report/webcore-result.txt"
set +e
timeout 4500s cmake --build "$build" --target WebCore --parallel 2 > "$report/webcore-build.log" 2>&1
status=$?
set -e
echo "WEBCORE_CMAKE_BUILD_EXIT=$status" | tee -a "$report/webcore-result.txt"
if [[ "$status" -ne 0 ]]; then
 echo 'WEBCORE_ROCKNIX_TARGET_BUILD=BLOCKED' | tee -a "$report/webcore-result.txt"
 grep -E -A 9 'FAILED:|fatal error:|error:|undefined reference|ninja: build stopped' \
  "$report/webcore-build.log" | head -n 160 > "$report/webcore-first-errors.txt" || true
 cat "$report/webcore-first-errors.txt"
 tail -n 45 "$report/webcore-build.log"
 echo 'WEBKIT_BROWSER_READY=no' >> "$report/webcore-result.txt"
 exit 10
fi
mapfile -t objects < <(find "$build" -type f -name '*.o' |
 grep '/WebCore.dir/' | sort)
if (( ${#objects[@]} < 100 )); then
 echo "ERROR: only ${#objects[@]} WebCore target objects (expect >=100)" >&2
 exit 11
fi
for obj in "${objects[@]}"; do
 readelf -h "$obj" | grep -Eq 'Class:[[:space:]]+ELF64'
 readelf -h "$obj" | grep -Eq 'Machine:[[:space:]]+AArch64'
done
{
 echo 'WEBCORE_ROCKNIX_TARGET_BUILD=PASS_REAL_AARCH64'
 echo "WEBCORE_AARCH64_OBJECTS=${#objects[@]}"
 echo 'TARGET_COMPILER=ROCKNIX_20260801_RK3326'
 echo 'WPE_PLATFORM=WAYLAND'
 echo 'GSTREAMER=OFF'
 echo 'COMPLETE_WEBKIT_LIBRARY_LINKED=no'
 echo 'TARGET_EXECUTED=no'
 echo 'R36H_INSTALLABLE=no'
} | tee -a "$report/webcore-result.txt"
cat "$report/webcore-result.txt" >> "$GITHUB_STEP_SUMMARY"
