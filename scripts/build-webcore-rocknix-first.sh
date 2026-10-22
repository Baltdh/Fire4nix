#!/usr/bin/env bash
# Compile WebCore object target with authentic ROCKNIX AArch64 SDK; no R36H firmware access.
set -euo pipefail
[[ "$GITHUB_ACTIONS" == true && "$(id -u)" != 0 ]] || exit 4
root="$GITHUB_WORKSPACE"
build="$root/wpe-unified-sdk-build/configure"
report="$root/wpe-unified-sdk-build/report"
cc="$root/rocknix-source/build.ROCKNIX-RK3326.aarch64/toolchain/bin/aarch64-rocknix-linux-gnu-gcc"
test "$("$cc" -dumpmachine)" = aarch64-rocknix-linux-gnu
test -s "$build/build.ninja" && test -s "$build/CMakeCache.txt"
grep -Fxq 'WPE_CMAKE_EXIT_CODE=0' "$report/status.txt"
grep -Fxq 'WPE_TARGET_CONFIGURE=CONFIGURED_REQUIRES_ABI_REVIEW' "$report/status.txt"
for option in 'USE_GSTREAMER:BOOL=OFF' 'ENABLE_WPE_PLATFORM_WAYLAND:BOOL=ON' 'USE_GBM:BOOL=OFF' 'USE_LIBDRM:BOOL=OFF'; do
 grep -Fxq "$option" "$build/CMakeCache.txt" || { echo "ERROR: cache option $option" >&2; exit 5; }
done
ninja -C "$build" -t targets all > "$report/webcore-targets.txt"
grep -Eq '^WebCore(:|[[:space:]])' "$report/webcore-targets.txt" || { echo 'ERROR: no WebCore target'; exit 8; }
echo 'WEBCORE_ROCKNIX_TARGET_BUILD=START' | tee "$report/webcore-result.txt"
set +e
timeout 3000s cmake --build "$build" --target WebCore --parallel 2 > "$report/webcore-build.log" 2>&1
rc=$?
set -e
echo "WEBCORE_BUILD_EXIT=$rc" | tee -a "$report/webcore-result.txt"
if [ "$rc" -ne 0 ]; then
 echo 'WEBCORE_ROCKNIX_TARGET_BUILD=BLOCKED' | tee -a "$report/webcore-result.txt"
 grep -E -A 8 'FAILED:|error:|fatal error:|ninja: build stopped|undefined reference' "$report/webcore-build.log" | head -n 160 > "$report/webcore-first-errors.txt" || true
 cat "$report/webcore-first-errors.txt"; tail -n 40 "$report/webcore-build.log"
 exit 10
fi
find "$build" -type f -name '*.o' -path '*/WebCore.dir/*' -print > "$report/webcore-object-paths.txt"
objects=$(wc -l < "$report/webcore-object-paths.txt")
test "$objects" -ge 100 || { echo "ERROR: only $objects WebCore objects" >&2; exit 11; }
while IFS= read -r object; do
 readelf -h "$object" | grep -Eq 'Class:[[:space:]]+ELF64' || exit 12
 readelf -h "$object" | grep -Eq 'Machine:[[:space:]]+AArch64' || exit 12
done < "$report/webcore-object-paths.txt"
{
 echo 'WEBCORE_ROCKNIX_TARGET_BUILD=PASS_REAL_AARCH64_OBJECTS'
 echo "WEBCORE_ARM64_OBJECTS=$objects"
 echo 'WPE_BROWSER_LINKED=no'
 echo 'TARGET_EXECUTED=no'
 echo 'R36H_INSTALLABLE=no'
} | tee -a "$report/webcore-result.txt"
cat "$report/webcore-result.txt" >> "$GITHUB_STEP_SUMMARY"
