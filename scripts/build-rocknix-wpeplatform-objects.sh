#!/usr/bin/env bash
# Compile ONLY genuine WPEPlatform object libraries against pinned ROCKNIX SDK.
# Never run AArch64 executables on host or deploy Ubuntu binaries to R36H.
set -euo pipefail
[[ ${GITHUB_ACTIONS:-} == true && $(id -u) != 0 && -n ${GITHUB_WORKSPACE:-} ]] || exit 4
repo="$GITHUB_WORKSPACE"
work="$repo/wpe-post-harfbuzz-probe"
build="$work/configure"
report="$work/report"
[[ -s "$build/build.ninja" && -s "$build/CMakeCache.txt" ]] || {
 echo 'ERROR: WPE CMake must fully configure before compiling objects' >&2; exit 4
}
grep -Fxq 'WPE_CMAKE_EXIT_CODE=0' "$report/status.txt"
grep -Fxq 'WPE_TARGET_CONFIGURE=CONFIGURED_REQUIRES_ABI_REVIEW' "$report/status.txt"
for setting in 'USE_GSTREAMER:BOOL=OFF' 'USE_LIBDRM:BOOL=OFF' \
 'USE_GBM:BOOL=OFF' 'ENABLE_WPE_PLATFORM_WAYLAND:BOOL=ON' \
 'ENABLE_WPE_PLATFORM_DRM:BOOL=OFF'; do
 grep -Fxq "$setting" "$build/CMakeCache.txt" || {
 echo "ERROR: unexpected CMake config $setting" >&2; exit 4; }
done
toolchain="$repo/rocknix-source/build.ROCKNIX-RK3326.aarch64/toolchain"
cc="$toolchain/bin/aarch64-rocknix-linux-gnu-gcc"
[[ $("$cc" -dumpmachine) == aarch64-rocknix-linux-gnu ]] || exit 4
echo 'WPEPLATFORM_CROSS_COMPILE=START'
if ! timeout 1100s cmake --build "$build" \
 --target WPEPlatform WPEPlatformWayland WPEPlatformHeadless \
 --parallel 2 > "$report/wpeplatform-target-build.log" 2>&1; then
 echo 'WPEPLATFORM_CROSS_COMPILE=BLOCKED'
 tail -n 110 "$report/wpeplatform-target-build.log"
 exit 10
fi
mapfile -t objects < <(find "$build" -type f -name '*.o' |
 grep -E '/WPEPlatform(Headless|Wayland)?\.dir/' | sort)
if (( ${#objects[@]} < 20 )); then
 echo "ERROR: too few WPEPlatform target objects: ${#objects[@]}" >&2; exit 11
fi
core=0; wayland=0; headless=0
for o in "${objects[@]}"; do
 readelf -h "$o" | grep -Eq 'Machine:[[:space:]]*AArch64' || {
 echo "ERROR: non-AArch64 WPEPlatform ELF $o" >&2; exit 11; }
 case "$o" in
 */WPEPlatform.dir/*) ((core+=1));;
 */WPEPlatformWayland.dir/*) ((wayland+=1));;
 */WPEPlatformHeadless.dir/*) ((headless+=1));;
 esac
done
((core >= 10 && wayland >= 1 && headless >= 1)) || {
 echo "ERROR: incomplete ARM64 WPEPlatform objects: $core/$wayland/$headless" >&2; exit 11
}
{
 echo 'WPEPLATFORM_REAL_ROCKNIX_AARCH64=PASS'
 echo "WPEPLATFORM_CORE_OBJECTS=$core"
 echo "WPEPLATFORM_WAYLAND_OBJECTS=$wayland"
 echo "WPEPLATFORM_HEADLESS_OBJECTS=$headless"
 echo "WPEPLATFORM_TOTAL_OBJECTS=${#objects[@]}"
 echo 'WPE_FULL_WEBKIT_COMPILED=no'
 echo 'R36H_RUNTIME_INSTALLABLE=no'
 echo 'TARGET_EXECUTED=no'
} | tee "$report/wpeplatform-target-result.txt"
cat "$report/wpeplatform-target-result.txt" >> "$GITHUB_STEP_SUMMARY"
