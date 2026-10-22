#!/usr/bin/env bash
# Compile a small, genuine WebCore source subset with ROCKNIX RK3326 GCC.
# This is a cross-build probe, not a complete WebKit browser.
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && "$(id -u)" != 0 && -n "${GITHUB_WORKSPACE:-}" ]] || {
 echo 'ERROR: non-root ephemeral GitHub runner required' >&2; exit 4;
}
work="$GITHUB_WORKSPACE/wpe-unified-sdk-build"
build="$work/configure"
report="$work/report"
cc="$GITHUB_WORKSPACE/rocknix-source/build.ROCKNIX-RK3326.aarch64/toolchain/bin/aarch64-rocknix-linux-gnu-gcc"
test -s "$build/build.ninja"
test -s "$build/CMakeCache.txt"
grep -Fxq 'WPE_CMAKE_EXIT_CODE=0' "$report/status.txt"
grep -Fxq 'WPE_TARGET_CONFIGURE=CONFIGURED_REQUIRES_ABI_REVIEW' "$report/status.txt"
grep -Fxq 'UNIFIED_ROCKNIX_SDK=PASS_STAGE1_15_ARTIFACTS' "$report/merge.txt"
test "$("$cc" -dumpmachine)" = aarch64-rocknix-linux-gnu
for setting in 'ENABLE_WPE_PLATFORM_WAYLAND:BOOL=ON' 'USE_GSTREAMER:BOOL=OFF' \
 'USE_LIBDRM:BOOL=OFF' 'USE_GBM:BOOL=OFF' 'ENABLE_GPU_PROCESS:BOOL=OFF';do
 grep -Fxq "$setting" "$build/CMakeCache.txt" || {
   echo "ERROR: wrong media or Wayland setting: $setting"; exit 4;
 }
done
ninja -C "$build" -t targets all > "$report/webcore-ninja-targets.txt"
# Select C++ source objects, not phony CMake rules or host code generators.
mapfile -t candidates < <(
  sed 's/: .*//' "$report/webcore-ninja-targets.txt" |
    grep -E '(^|/)CMakeFiles/WebCore[^/]*\.dir/.*\.(cpp|cc)\.o$' |
    grep -Ev '/(bindings|inspector|css)/' | sort -u | head -n 3
)
if (( ${#candidates[@]} < 1 ));then
 echo 'WEBCORE_TARGET_DISCOVERY=BLOCKED_NO_SOURCE_OBJECTS' | tee "$report/webcore-first-result.txt"
 grep -i 'WebCore' "$report/webcore-ninja-targets.txt" | head -n 45 || true
 exit 8
fi
printf 'WEBCORE_SELECTED_SOURCE_OBJECT=%s\n' "${candidates[@]}" |
 tee "$report/webcore-selected.txt"
done_count=0
for item in "${candidates[@]}";do
 echo "WEBCORE_COMPILE_START=$item" | tee -a "$report/webcore-first-result.txt"
 set +e
 timeout 1500s ninja -C "$build" -j 2 "$item" \
   >> "$report/webcore-compile.log" 2>&1
 rc=$?
 set -e
 if [ "$rc" -ne 0 ];then
   echo "WEBCORE_COMPILE_BLOCKED=$item exit=$rc" | tee -a "$report/webcore-first-result.txt"
   grep -E -A 7 'FAILED:|error:|fatal error:|undefined reference|ninja: build stopped' \
     "$report/webcore-compile.log" | head -n 130 > "$report/webcore-first-errors.txt" || true
   cat "$report/webcore-first-errors.txt"
   tail -n 50 "$report/webcore-compile.log"
   exit 10
 fi
 target_elf="$build/$item"
 test -s "$target_elf" || { echo "ERROR: missing object: $item"; exit 11; }
 readelf -h "$target_elf" | grep -Eq 'Class:[[:space:]]+ELF64'
 readelf -h "$target_elf" | grep -Eq 'Machine:[[:space:]]+AArch64'
 readelf -h "$target_elf" | grep -Eq "Data:.*little endian"
 done_count=$((done_count+1))
done
{
 echo "WEBCORE_REAL_ROCKNIX_AARCH64_OBJECTS=$done_count"
 echo 'WEBCORE_FIRST_OBJECTS=PASS_REAL_TARGET_COMPILER'
 echo 'WEBCORE_FULL_BUILD=no'
 echo 'WPE_WEBKIT_BUILT=no'
 echo 'R36H_INSTALLABLE=no'
 echo 'TARGET_EXECUTED=no'
} | tee -a "$report/webcore-first-result.txt"
cat "$report/webcore-first-result.txt" >> "$GITHUB_STEP_SUMMARY"
