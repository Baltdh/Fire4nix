#!/usr/bin/env bash
# Real ROCKNIX RK3326 JavaScriptCore build: no target ELF execution.
set -euo pipefail
[[ ${GITHUB_ACTIONS:-} == true && $(id -u) != 0 && -n ${GITHUB_WORKSPACE:-} ]] || exit 4
work="$GITHUB_WORKSPACE/wpe-post-harfbuzz-probe"
build="$work/configure"
report="$work/report"
sdk="$GITHUB_WORKSPACE/rocknix-source/build.ROCKNIX-RK3326.aarch64/toolchain"
[[ -s "$build/build.ninja" && -s "$build/CMakeCache.txt" ]] || exit 4
grep -Fxq 'WPEPLATFORM_REAL_ROCKNIX_AARCH64=PASS' "$report/wpeplatform-target-result.txt"
for opt in 'USE_GSTREAMER:BOOL=OFF' 'ENABLE_WPE_PLATFORM_WAYLAND:BOOL=ON' \
           'ENABLE_WPE_PLATFORM_DRM:BOOL=OFF'; do
  grep -Fxq "$opt" "$build/CMakeCache.txt" || { echo "ERROR: unexpected flag $opt"; exit 4; }
done
[[ $("$sdk/bin/aarch64-rocknix-linux-gnu-gcc" -dumpmachine) == aarch64-rocknix-linux-gnu ]]
echo 'JSC_ROCKNIX_CROSS_COMPILE=START'
if ! timeout 2100s cmake --build "$build" --target jsc --parallel 2 \
    > "$report/jsc-rocknix-build.log" 2>&1; then
  echo 'JSC_ROCKNIX_CROSS_COMPILE=BLOCKED_OR_TIMED_OUT'
  tail -n 130 "$report/jsc-rocknix-build.log"
  exit 10
fi
echo 'JSC_ROCKNIX_CROSS_COMPILE=PASS'
mapfile -t objects < <(find "$build" -type f -name '*.o' \
  | grep -E '/(JavaScriptCore|JavaScriptCoreJIT|LowLevelInterpreterLib)\.dir/' | sort)
(( ${#objects[@]} >= 50 )) || { echo "ERROR: only ${#objects[@]} JSC objects"; exit 11; }
for obj in "${objects[@]}"; do
  readelf -h "$obj" | grep -Eq 'Machine:[[:space:]]*AArch64' || {
    echo "ERROR: non-AArch64 JSC object $obj"; exit 11; }
done
jsc=''
for candidate in "$build/bin/jsc" "$build/Programs/jsc" "$build/Source/JavaScriptCore/jsc"; do
  [[ -x "$candidate" && -f "$candidate" ]] && { jsc="$candidate"; break; }
done
[[ -n "$jsc" ]] || jsc=$(find "$build" -type f -name jsc -perm /111 -print -quit)
[[ -n "$jsc" && -s "$jsc" ]] || { echo 'ERROR: linked jsc not found'; exit 11; }
readelf -h "$jsc" > "$report/jsc-target-elf-header.txt"
readelf -d "$jsc" > "$report/jsc-target-elf-dynamic.txt"
readelf -V "$jsc" > "$report/jsc-target-elf-versions.txt"
grep -Eq 'Class:[[:space:]]*ELF64' "$report/jsc-target-elf-header.txt"
grep -Eq 'Machine:[[:space:]]*AArch64' "$report/jsc-target-elf-header.txt"
if grep -Eq 'TEXTREL|Shared library: \[libgst' "$report/jsc-target-elf-dynamic.txt"; then
  echo 'ERROR: forbidden GStreamer dependency'; exit 12
fi
python3 - "$report/jsc-target-elf-versions.txt" <<'PY'
import re,sys
v=[tuple(map(int,x.split('.'))) for x in re.findall(r'Name: GLIBC_([0-9.]+)',open(sys.argv[1]).read())]
assert all(x <= (2,41) for x in v),v
print('JSC_TARGET_GLIBC=PASS_MAX_2_41')
PY
{
 echo 'JSC_REAL_ROCKNIX_AARCH64=PASS_COMPILER_LINK_ELF'
 echo "JSC_REAL_TARGET_OBJECTS=${#objects[@]}"
 echo 'JSC_EXECUTABLE=ELF64_AARCH64'
 echo 'TARGET_EXECUTED=no'
 echo 'WEBKIT_FULL_BROWSER_COMPILED=no'
 echo 'R36H_INSTALLABLE=no'
} | tee "$report/jsc-rocknix-result.txt"
cat "$report/jsc-rocknix-result.txt" >> "$GITHUB_STEP_SUMMARY"
