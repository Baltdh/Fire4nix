#!/usr/bin/env bash
# Cross-compile and link the genuine WPEWebKit 2.54.1 shared library for RK3326.
# This is an isolated CI experiment; no ARM64 execution and NO device install.
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && "$(id -u)" != 0 && -n "${GITHUB_WORKSPACE:-}" ]] || {
 echo 'ERROR: non-root GitHub runner only' >&2; exit 4;
}
root="$GITHUB_WORKSPACE"
work="$root/wpe-unified-sdk-build"
build="$work/configure"
report="$work/report"
sdk="$root/rocknix-source/build.ROCKNIX-RK3326.aarch64/toolchain"
test -s "$build/build.ninja" && test -s "$build/CMakeCache.txt"
test "$("$sdk/bin/aarch64-rocknix-linux-gnu-gcc" -dumpmachine)" = aarch64-rocknix-linux-gnu
grep -Fxq 'WPE_CMAKE_EXIT_CODE=0' "$report/status.txt"
grep -Fxq 'WPE_TARGET_CONFIGURE=CONFIGURED_REQUIRES_ABI_REVIEW' "$report/status.txt"
grep -Fxq 'UNIFIED_ROCKNIX_SDK=PASS_STAGE1_15_ARTIFACTS' "$report/merge.txt"
for key in 'ENABLE_WPE_PLATFORM_WAYLAND:BOOL=ON' 'USE_GSTREAMER:BOOL=OFF' \
 'USE_LIBDRM:BOOL=OFF' 'USE_GBM:BOOL=OFF' 'ENABLE_GPU_PROCESS:BOOL=OFF'; do
 grep -Fxq "$key" "$build/CMakeCache.txt" || {
  echo "ERROR: unexpected WPE feature state: $key" >&2; exit 5;
 }
done
# WPE source PlatformWPE.cmake names its library WebKit and sets the output
# name WPEWebKit-2.0. Avoid confusing source target with installed filename.
ninja -C "$build" -t targets all > "$report/webkit-targets.txt"
grep -Eq '^WebKit:([[:space:]]|$)' "$report/webkit-targets.txt" || {
 echo 'ERROR: upstream WPE 2.54.1 WebKit target not found' >&2
 grep -E '(^|/)WebKit|WebProcess|NetworkProcess' "$report/webkit-targets.txt" | head -n 60 || true
 exit 8
}
echo 'WPEWEBKIT_ROCKNIX_LIBRARY_BUILD=START' | tee "$report/webkit-library-result.txt"
set +e
timeout 10500s cmake --build "$build" --target WebKit --parallel 2 > "$report/webkit-library-build.log" 2>&1
rc=$?
set -e
echo "WPEWEBKIT_CMAKE_BUILD_EXIT=$rc" | tee -a "$report/webkit-library-result.txt"
if (( rc != 0 )); then
 echo 'WPEWEBKIT_ROCKNIX_LIBRARY_BUILD=BLOCKED' | tee -a "$report/webkit-library-result.txt"
 grep -E -A 7 'FAILED:|fatal error:|error:|undefined reference|ninja: build stopped' \
   "$report/webkit-library-build.log" | head -n 180 > "$report/webkit-library-first-errors.txt" || true
 cat "$report/webkit-library-first-errors.txt"
 tail -n 70 "$report/webkit-library-build.log"
 echo 'R36H_INSTALLABLE=no' >> "$report/webkit-library-result.txt"
 exit 10
fi
mapfile -t candidates < <(find "$build" -type f -name 'libWPEWebKit-2.0.so*' | sort)
if (( ${#candidates[@]} == 0 )); then
 echo 'ERROR: WebKit target completed but no libWPEWebKit-2.0.so ELF produced' >&2
 find "$build" -type f \( -name '*WebKit*.so*' -o -name '*WebKit*.a' \) | head -n 35
 exit 11
fi
chosen=""
for candidate in "${candidates[@]}"; do
 if readelf -h "$candidate" 2>/dev/null | grep -Eq 'Machine:[[:space:]]+AArch64'; then
  chosen="$candidate"
  break
 fi
done
test -n "$chosen" || { echo 'ERROR: only foreign-architecture WPE libraries found' >&2; exit 11; }
readelf -h "$chosen" > "$report/webkit-library-elf-header.txt"
readelf -d "$chosen" > "$report/webkit-library-dynamic.txt"
readelf -V "$chosen" > "$report/webkit-library-version-info.txt"
grep -Eq 'Class:[[:space:]]+ELF64' "$report/webkit-library-elf-header.txt"
grep -Eq 'Data:.*little endian' "$report/webkit-library-elf-header.txt"
grep -Eq 'Machine:[[:space:]]+AArch64' "$report/webkit-library-elf-header.txt"
grep -Eq '\(SONAME\).*\[libWPEWebKit-2\.0\.so\.1\]' "$report/webkit-library-dynamic.txt" || {
 echo 'ERROR: WPE 2.0 target ABI SONAME not verified' >&2; exit 12;
}
if grep -Eq '\(TEXTREL\)|Shared library: \[libgst' "$report/webkit-library-dynamic.txt"; then
 echo 'ERROR: text relocations or GStreamer dependency in WPE shared library' >&2; exit 12
fi
python3 - "$report/webkit-library-version-info.txt" <<'PY'
import re,sys
data=open(sys.argv[1]).read()
versions=[(int(major),int(minor)) for major,minor in re.findall(r'Name: GLIBC_(\d+)\.(\d+)',data)]
assert all(version <= (2,41) for version in versions),versions
print('WPEWEBKIT_TARGET_GLIBC=PASS_MAX_2_41')
PY
# Preserve the actual linked binary for the next private WebKit process stage.
# Not installable: missing processes, resources, ABI/runtime checks and tests.
mkdir -p "$root/wpe-link-output"
cp -L "$chosen" "$root/wpe-link-output/libWPEWebKit-2.0.so.1"
sha256sum "$root/wpe-link-output/libWPEWebKit-2.0.so.1" > "$report/webkit-library-sha256.txt"
{
 echo 'WPEWEBKIT_ROCKNIX_LIBRARY_BUILD=PASS_REAL_AARCH64_LINKED'
 echo "WPEWEBKIT_LIBRARY_ELF=$chosen"
 echo 'WPE_WEBKIT_PROCESSES_BUILT=NOT_VERIFIED'
 echo 'WPE_RUNTIME_DEPENDENCY_CLOSURE=NOT_VERIFIED'
 echo 'WEBKIT_RENDERED_ON_R36H=no'
 echo 'R36H_INSTALLABLE=no'
 echo 'TARGET_EXECUTED=no'
} | tee -a "$report/webkit-library-result.txt"
cat "$report/webkit-library-result.txt" >> "$GITHUB_STEP_SUMMARY"
