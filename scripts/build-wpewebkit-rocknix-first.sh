#!/usr/bin/env bash
# Build and statically audit a real WPE WebKit 2.54.1 shared library using
# the pinned ROCKNIX RK3326 cross compiler. No target executable is run.
set -euo pipefail

[[ "$GITHUB_ACTIONS" == "true" && "$(id -u)" -ne 0 && -n "$GITHUB_WORKSPACE" ]] || {
  echo 'ERROR: use a non-root GitHub Actions runner only' >&2; exit 4;
}
root="$GITHUB_WORKSPACE"
work="$root/wpe-unified-sdk-build"
build="$work/configure"
report="$work/report"
sdk="$root/rocknix-source/build.ROCKNIX-RK3326.aarch64/toolchain"
stage="$root/stage1-artifact/stage1-combined"

test -s "$build/build.ninja"
test -s "$build/CMakeCache.txt"
test -s "$report/status.txt"
test -s "$report/merge.txt"
test -s "$stage/usr/lib/libglib-2.0.so.0"
test -s "$stage/usr/lib/libharfbuzz.so.0"
test -x "$sdk/bin/aarch64-rocknix-linux-gnu-g++"
test "$("$sdk/bin/aarch64-rocknix-linux-gnu-gcc" -dumpmachine)" = aarch64-rocknix-linux-gnu
grep -Fxq 'WPE_CMAKE_EXIT_CODE=0' "$report/status.txt"
grep -Fxq 'WPE_TARGET_CONFIGURE=CONFIGURED_REQUIRES_ABI_REVIEW' "$report/status.txt"
grep -Fxq 'UNIFIED_ROCKNIX_SDK=PASS_STAGE1_15_ARTIFACTS' "$report/merge.txt"

for setting in \
 'PORT:STRING=WPE' \
 'ENABLE_WPE_PLATFORM:BOOL=ON' \
 'ENABLE_WPE_PLATFORM_WAYLAND:BOOL=ON' \
 'USE_GSTREAMER:BOOL=OFF' \
 'USE_LIBDRM:BOOL=OFF' \
 'USE_GBM:BOOL=OFF' \
 'ENABLE_GPU_PROCESS:BOOL=OFF'; do
 # PORT may be declared UNINITIALIZED in the cache: accept an exact value.
 if [[ "$setting" == PORT:* ]]; then
   grep -Eq '^PORT:[A-Z_]+=WPE$' "$build/CMakeCache.txt" || exit 5
 else
   grep -Fxq "$setting" "$build/CMakeCache.txt" || {
     echo "ERROR: forbidden/incorrect CMake setting $setting" >&2; exit 5;
   }
 fi
done

ninja -C "$build" -t targets all > "$report/available-ninja-targets.txt"
# Upstream WebKit defines CMake target 'WebKit' and WPE sets its OUTPUT_NAME
# to WPEWebKit-2.0; never confuse the resulting filename with the target.
if grep -Eq '^WebKit:[[:space:]]' "$report/available-ninja-targets.txt"; then
  target=WebKit
elif grep -Eq '^WPEWebKit:[[:space:]]' "$report/available-ninja-targets.txt"; then
  target=WPEWebKit
else
  echo 'WPE_WEBKIT_LINK=NO_NINJA_TARGET' | tee "$report/wpewebkit-link-result.txt"
  grep -iE 'webkit|webcore|javascriptcore' "$report/available-ninja-targets.txt" | head -n 45 || true
  exit 6
fi

{
  echo 'WPE_WEBKIT_LINK=START'
  echo "WPE_WEBKIT_NINJA_TARGET=$target"
  echo 'ROCKNIX_COMPILER=aarch64-rocknix-linux-gnu'
  echo 'WPE_MEDIA_PROFILE=NO_GSTREAMER'
  echo 'TARGET_EXECUTED=no'
  echo 'R36H_INSTALLABLE=no'
} | tee "$report/wpewebkit-link-result.txt"
df -h "$build" >> "$report/disk-and-memory.txt"
free -h >> "$report/disk-and-memory.txt"

set +e
timeout --signal=TERM --kill-after=20s 11280s \
  cmake --build "$build" --target "$target" --parallel 2 \
  > "$report/wpewebkit-build.log" 2>&1
rc=$?
set -e
echo "WPE_WEBKIT_CMAKE_EXIT=$rc" | tee -a "$report/wpewebkit-link-result.txt"
if (( rc != 0 )); then
  if (( rc == 124 || rc == 137 )); then
    echo 'WPE_WEBKIT_LINK_FAILURE=TIME_OR_RESOURCE_LIMIT' | tee -a "$report/wpewebkit-link-result.txt"
  else
    echo 'WPE_WEBKIT_LINK_FAILURE=BUILD_OR_LINK_ERROR' | tee -a "$report/wpewebkit-link-result.txt"
  fi
  echo 'WPE_WEBKIT_LINK=BLOCKED' | tee -a "$report/wpewebkit-link-result.txt"
  grep -E -A 8 'FAILED:|fatal error:|error:|undefined reference|ld: |collect2:|ninja: build stopped|Killed' \
    "$report/wpewebkit-build.log" | head -n 180 > "$report/wpewebkit-first-errors.txt" || true
  cat "$report/wpewebkit-first-errors.txt"
  tail -n 35 "$report/wpewebkit-build.log"
  exit 10
fi

# Source build may contain symlink aliases. Verify an actual file, not a
# dangling alias or a file from /usr/lib on the host runner.
found=''
while IFS= read -r -d '' file; do
  if readelf -d "$file" 2>/dev/null | grep -Eq '\(SONAME\).*\[libWPEWebKit-2\.0\.so\.1\]'; then
    found="$file"
    break
  fi
done < <(find "$build" -type f -name 'libWPEWebKit-2.0.so*' -print0)

if [[ -z "$found" ]]; then
  echo 'WPE_WEBKIT_LINK=NO_REAL_SONAME_LIBRARY' | tee -a "$report/wpewebkit-link-result.txt"
  find "$build" -name 'libWPEWebKit*' -print | head -n 30 || true
  exit 11
fi

echo "WPE_WEBKIT_LIBRARY_PATH=$found" | tee -a "$report/wpewebkit-link-result.txt"
python3 "$root/fire4nix/scripts/verify-built-wpewebkit.py" \
  --library "$found" --report "$report/wpewebkit-elf-audit.txt" || {
    echo 'WPE_WEBKIT_LINK=ELF_AUDIT_BLOCKED' | tee -a "$report/wpewebkit-link-result.txt"
    exit 12
  }

# Non-installable diagnostic artifact: only the audited engine library. It
# explicitly excludes subprocesses, TLS modules and private dependencies.
mkdir -p "$work/linked-elf"
cp -- "$found" "$work/linked-elf/libWPEWebKit-2.0.so.1"
sha256sum "$work/linked-elf/libWPEWebKit-2.0.so.1" > "$work/linked-elf/SHA256SUMS"
{
  echo 'WPE_WEBKIT_LINK=PASS_REAL_AARCH64_LIBRARY'
  echo 'WPE_SUBPROCESSES_BUILT=NOT_TESTED'
  echo 'WPE_RUNTIME_ABI_COMPLETE=no'
  echo 'WPE_HTTPS_TESTED=no'
  echo 'WPE_R36H_GUI_TESTED=no'
  echo 'R36H_INSTALLABLE=no'
} | tee -a "$report/wpewebkit-link-result.txt"
cat "$report/wpewebkit-link-result.txt" >> "$GITHUB_STEP_SUMMARY"
