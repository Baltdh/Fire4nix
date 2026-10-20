#!/usr/bin/env bash
# Real JavaScriptCore (JSC shell + engine) smoke build, on isolated Ubuntu ARM64 CI.
# Not a ROCKNIX sysroot build, not an R36H executable, not a working web browser.
set -euo pipefail
case ${1:---check} in
  --check) ;;
  --help) echo 'FIRE4NIX_BUILD_WORK=/tmp/... bash scripts/build-jsc-aarch64-smoke.sh --check'; exit 0 ;;
  *) echo 'ERROR: use --check' >&2; exit 2 ;;
esac
[ "$(uname -m)" = aarch64 ] || { echo 'ERROR: native AArch64 runner required' >&2; exit 4; }
work=${FIRE4NIX_BUILD_WORK:-}
[ -n "$work" ] && [ -f "$work/wpe-cmake/build.ninja" ] || {
  echo 'ERROR: WPE 2.54.1 must be CMake-configured first' >&2; exit 4
}
repo=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
report_dir="$work/reports"
mkdir -p "$report_dir"
FIRE4NIX_WPE_BUILD_DIR="$work/wpe-cmake" FIRE4NIX_MEDIA_PROFILE=minimal \
  sh "$repo/rocknix-integration/verify-wpe-media-cache.sh" --check \
  > "$report_dir/jsc-media-cache-check.txt"
grep -Fqx 'MEDIA_CACHE_STATUS=PASS_WPE_WAYLAND_WITHOUT_GSTREAMER' \
  "$report_dir/jsc-media-cache-check.txt"
echo 'JSC_AARCH64_BUILD=START'
if ! timeout 2100s cmake --build "$work/wpe-cmake" --target jsc \
    --parallel "${FIRE4NIX_JSC_BUILD_JOBS:-2}" \
    > "$report_dir/jsc-build.log" 2>&1; then
  status=$?
  # Avoid using $? after ! (it is 0 on failure of !); use explicit reporting.
  echo "JSC_AARCH64_BUILD=FAILED_OR_TIMED_OUT"
  echo 'JSC_TEST_STATUS=BLOCKED'
  tail -n 110 "$report_dir/jsc-build.log"
  exit 10
fi
echo 'JSC_AARCH64_BUILD=COMPLETED'
jsc=''
for candidate in "$work/wpe-cmake/bin/jsc" "$work/wpe-cmake/Programs/jsc" \
                 "$work/wpe-cmake/Source/JavaScriptCore/jsc"; do
  if [ -f "$candidate" ] && [ -x "$candidate" ]; then jsc=$candidate; break; fi
done
if [ -z "$jsc" ]; then
  jsc=$(find "$work/wpe-cmake" -type f -name jsc -perm /111 -print -quit)
fi
[ -n "$jsc" ] && [ -f "$jsc" ] || {
  echo 'ERROR: JSC executable absent after completed build' >&2; exit 10
}
readelf -h "$jsc" | grep -Eq 'Machine:[[:space:]]+AArch64' || {
  echo 'ERROR: JSC shell is not AArch64 ELF' >&2; exit 10
}
echo 'JSC_ELF=AARCH64'
# The private JS engine can have its own CMake RPATH. Keep the target runtime
# entirely inside isolated build + private dependencies; NEVER use on R36H.
export LD_LIBRARY_PATH="$work/wpe-cmake/lib:$work/arm64-prerequisites/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
js="$repo/native/tests/jsc-webkit-runtime-smoke.js"
[ -s "$js" ] || { echo 'ERROR: JSC runtime smoke JavaScript missing' >&2; exit 4; }
if ! timeout 90s "$jsc" "$js" > "$report_dir/jsc-run.txt" 2>&1; then
  echo 'JSC_RUN=FAILED'
  tail -n 100 "$report_dir/jsc-run.txt"
  exit 11
fi
grep -Fqx 'FIRE4NIX_JSC_RUNTIME=PASS_ES6_ARRAY_MAP_JSON_AND_BIGINT' \
  "$report_dir/jsc-run.txt" || {
  echo 'ERROR: JavaScriptCore did not emit expected test success' >&2
  cat "$report_dir/jsc-run.txt"
  exit 11
}
echo 'JSC_RUNTIME=PASS'
# Independently audit executable and linked private JS engine ELF versions.
engine=$(find "$work/wpe-cmake" -type f -name 'libJavaScriptCore*.so*' -print -quit)
[ -n "$engine" ] || { echo 'ERROR: linked JavaScriptCore shared object not found' >&2; exit 10; }
max_ver() {
  readelf --version-info "$1" 2>/dev/null |
    sed -n 's/.*Name: GLIBC_\([0-9][0-9.]*\).*/\1/p' | sort -V | tail -1 || true
}
{
  echo 'JSC_SMOKE=PASS_REAL_ENGINE_AND_JSC_EXECUTABLE'
  echo 'JSC_TARGET=ELF64_AARCH64'
  echo 'JSC_SOURCE_VERSION=wpewebkit-2.54.1'
  echo 'CMAKE_GSTREAMER=OFF'
  echo 'WEBKIT_FULL_BROWSER_COMPILED=no'
  echo 'ROCKNIX_SYSROOT_USED=no'
  echo 'TARGET_HARDWARE_TESTED=no'
  echo 'R36H_INSTALLABLE=no'
  echo "JSC_CLI=$(basename "$jsc")"
} > "$report_dir/JSC-AARCH64-EXECUTION.txt"
for elf in "$jsc" "$engine"; do
  readelf -h "$elf" | grep -Eq 'Machine:[[:space:]]+AArch64' || {
    echo "ERROR: non-AArch64 ELF: $elf" >&2; exit 10
  }
  req=$(max_ver "$elf")
  if [ -n "$req" ] && ! awk -v req="$req" 'BEGIN {
      split(req,a,"."); exit !(a[1]<2 || (a[1]==2 && a[2]<=41))
    }'; then
    echo "ERROR: $elf needs GLIBC_$req, newer than R36H GLIBC_2.41" >&2
    exit 12
  fi
  echo "AUDITED_ELF=$(basename "$elf") glibc_max=${req:-none}" \
    >> "$report_dir/JSC-AARCH64-EXECUTION.txt"
done
cat "$report_dir/JSC-AARCH64-EXECUTION.txt"
echo 'JSC_SMOKE_END=PASS'
