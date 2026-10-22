#!/usr/bin/env bash
# First real JavaScriptCore target build using ROCKNIX 20260801 RK3326 toolchain.
# Build artefact only. Does not run any target binaries, change firmware or
# enable unsafe browser sandbox settings on the R36H device.
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && "$(id -u)" != 0 && -n "${GITHUB_WORKSPACE:-}" ]] || {
 echo 'ERROR: this cross-build is restricted to a non-root GitHub runner' >&2; exit 4;
}
root="$GITHUB_WORKSPACE"
work="$root/wpe-unified-sdk-build"
build="$work/configure"
report="$work/report"
stage="$root/stage1-artifact/stage1-combined"
cc="$root/rocknix-source/build.ROCKNIX-RK3326.aarch64/toolchain/bin/aarch64-rocknix-linux-gnu-gcc"
test -s "$build/build.ninja"
test -s "$build/CMakeCache.txt"
test -s "$report/status.txt"
test "$("$cc" -dumpmachine)" = aarch64-rocknix-linux-gnu
grep -Fxq 'WPE_CMAKE_EXIT_CODE=0' "$report/status.txt"
grep -Fxq 'WPE_TARGET_CONFIGURE=CONFIGURED_REQUIRES_ABI_REVIEW' "$report/status.txt"
grep -Fxq 'UNIFIED_ROCKNIX_SDK=PASS_STAGE1_15_ARTIFACTS' "$report/merge.txt"
for kv in 'ENABLE_WPE_PLATFORM_WAYLAND:BOOL=ON' 'USE_GSTREAMER:BOOL=OFF' \
  'USE_LIBDRM:BOOL=OFF' 'USE_GBM:BOOL=OFF' 'ENABLE_GPU_PROCESS:BOOL=OFF'; do
 grep -Fxq "$kv" "$build/CMakeCache.txt" || {
  echo "ERROR: forbidden/incorrect WPE cache option: $kv" >&2; exit 4;
 }
done
test -s "$stage/usr/lib/libglib-2.0.so.0"
test -s "$stage/usr/lib/libharfbuzz.so.0"
# -t targets is a read-only list; avoids accidentally building the wrong target.
if ! ninja -C "$build" -t targets all | grep -Eq '^JavaScriptCore(:|[[:space:]])'; then
 echo 'ERROR: JavaScriptCore Ninja target not exported' >&2
 ninja -C "$build" -t targets all | grep -i javascriptcore | head -n 30 || true
 exit 8
fi
echo 'JAVASCRIPTCORE_ROCKNIX_TARGET_BUILD=START' | tee "$report/javascriptcore-result.txt"
set +e
timeout 3600s cmake --build "$build" --target JavaScriptCore --parallel 2 \
 > "$report/javascriptcore-build.log" 2>&1
status=$?
set -e
printf 'JAVASCRIPTCORE_CMAKE_BUILD_EXIT=%s\n' "$status" | tee -a "$report/javascriptcore-result.txt"
if [ "$status" -ne 0 ]; then
 echo 'JAVASCRIPTCORE_ROCKNIX_TARGET_BUILD=BLOCKED' | tee -a "$report/javascriptcore-result.txt"
 grep -E -A 10 'FAILED:|error:|fatal error:|ninja: build stopped|undefined reference' \
  "$report/javascriptcore-build.log" | head -n 160 > "$report/javascriptcore-first-errors.txt" || true
 cat "$report/javascriptcore-first-errors.txt"
 tail -n 35 "$report/javascriptcore-build.log"
 echo 'WEBKIT_BROWSER_READY=no' >> "$report/javascriptcore-result.txt"
 exit 10
fi
mapfile -t objs < <(find "$build" -type f -name '*.o' | grep '/JavaScriptCore.dir/' | sort)
if (( ${#objs[@]} < 100 ));then
 echo "ERROR: suspiciously few target JavaScriptCore ELF objects: ${#objs[@]}" >&2
 exit 11
fi
for obj in "${objs[@]}";do
 head=$(readelf -h "$obj") || exit 11
 printf '%s\n' "$head" | grep -Eq 'Class:[[:space:]]+ELF64' || exit 11
 printf '%s\n' "$head" | grep -Eq 'Machine:[[:space:]]+AArch64' || exit 11
done
{
 echo 'JAVASCRIPTCORE_ROCKNIX_TARGET_BUILD=PASS_REAL_AARCH64'
 echo "JAVASCRIPTCORE_ARM64_OBJECTS=${#objs[@]}"
 echo 'WPE_WEBKIT_FULL_BUILD=no'
 echo 'R36H_INSTALLABLE=no'
 echo 'TARGET_EXECUTED=no'
} | tee -a "$report/javascriptcore-result.txt"
cat "$report/javascriptcore-result.txt" >> "$GITHUB_STEP_SUMMARY"
