#!/usr/bin/env bash
# Exercise target discovery with a large graph, without compiling WebKit.
set -euo pipefail
repo=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
mkdir -p "$t/bin" "$t/work/wpe-cmake"
touch "$t/work/wpe-cmake/build.ninja"
export FIRE4NIX_BUILD_WORK="$t/work" TEST_TARGET_ROOT="$t"
export PATH="$t/bin:$PATH"
cat > "$t/bin/uname" <<'MOCK'
#!/bin/sh
echo aarch64
MOCK
cat > "$t/bin/ninja" <<'MOCK'
#!/usr/bin/env python3
import os, sys
root = os.environ['TEST_TARGET_ROOT']
with open(root + '/calls', 'a') as f:
    f.write('ninja\n')
mode = os.environ.get('TEST_TARGET_MODE', 'valid')
print('WPEPlatform: phony')
print('WPEPlatformWayland: phony')
if mode != 'missing':
    print('WPEPlatformHeadless: phony')
else:
    print('WPEPlatformHeadlessExtra: phony')
for i in range(50000):
    print('Source/WebCore/CMakeFiles/WebCore.dir/generated/LongTarget%d.o: CXX_COMPILER' % i)
sys.exit(7 if mode == 'failure' else 0)
MOCK
cat > "$t/bin/cmake" <<'MOCK'
#!/bin/sh
touch "$TEST_TARGET_ROOT/build-reached"
# Stop at the boundary: no actual compiler or fake success artifact.
exit 42
MOCK
chmod +x "$t/bin/"*
for key in ENABLE_WPE_PLATFORM ENABLE_WPE_PLATFORM_WAYLAND; do
  echo "$key:BOOL=ON"
done > "$t/work/wpe-cmake/CMakeCache.txt"
for key in ENABLE_WPE_LEGACY_API USE_GSTREAMER USE_GSTREAMER_GL ENABLE_VIDEO ENABLE_WEB_AUDIO ENABLE_SPEECH_SYNTHESIS ENABLE_WEB_CODECS ENABLE_MEDIA_STREAM ENABLE_WEB_RTC ENABLE_MEDIA_RECORDER ENABLE_INTROSPECTION ENABLE_DOCUMENTATION; do
  echo "$key:BOOL=OFF"
done >> "$t/work/wpe-cmake/CMakeCache.txt"
run_case() {
  export TEST_TARGET_MODE=$1
  rm -f "$t/build-reached" "$t/calls"
  set +e
  bash "$repo/scripts/build-wpeplatform-aarch64-objects.sh" > "$t/output" 2>&1
  status=$?
  set -e
  test "$status" -eq "$2" || { cat "$t/output"; exit 1; }
  test "$(wc -l < "$t/calls")" -eq 1
}
run_case valid 10
test -f "$t/build-reached"
grep -q '^WPEPLATFORM_ARM64_BUILD=FAILED$' "$t/output"
run_case missing 5
test ! -e "$t/build-reached"
grep -q 'missing WPEPlatformHeadless build target' "$t/output"
run_case failure 5
test ! -e "$t/build-reached"
grep -q 'could not enumerate Ninja targets' "$t/output"
echo 'PASS: large Ninja graph consumed once; missing target and producer failure block build'
