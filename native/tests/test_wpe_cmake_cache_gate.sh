#!/bin/sh
# No SDK, network, WebKit runtime or real device needed.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
GUARD="$ROOT/rocknix-integration/verify-wpe-media-cache.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' 0
cat > "$T/CMakeCache.txt" <<'CACHE'
// Mock CMake cache, not a compiled WebKit build.
ENABLE_WPE_PLATFORM:BOOL=ON
ENABLE_WPE_PLATFORM_WAYLAND:BOOL=ON
ENABLE_WPE_LEGACY_API:BOOL=OFF
USE_GSTREAMER:BOOL=OFF
USE_GSTREAMER_GL:BOOL=OFF
ENABLE_VIDEO:BOOL=OFF
ENABLE_WEB_AUDIO:BOOL=OFF
ENABLE_SPEECH_SYNTHESIS:BOOL=OFF
ENABLE_WEB_CODECS:BOOL=OFF
ENABLE_MEDIA_STREAM:BOOL=OFF
ENABLE_WEB_RTC:BOOL=OFF
ENABLE_MEDIA_RECORDER:BOOL=OFF
ENABLE_INTROSPECTION:BOOL=OFF
ENABLE_DOCUMENTATION:BOOL=OFF
CACHE
FIRE4NIX_WPE_BUILD_DIR="$T" sh "$GUARD" --check > "$T/valid"
grep -q '^MEDIA_CACHE_STATUS=PASS_' "$T/valid"
sed -i 's/USE_GSTREAMER:BOOL=OFF/USE_GSTREAMER:BOOL=ON/' "$T/CMakeCache.txt"
if FIRE4NIX_WPE_BUILD_DIR="$T" sh "$GUARD" --check > "$T/reject"; then
  echo 'FAIL: accepted GStreamer-linked WPE configuration' >&2; exit 1
fi
grep -q 'CACHE_WRONG=USE_GSTREAMER actual=ON expected=OFF' "$T/reject"
grep -q '^MEDIA_CACHE_STATUS=BLOCKED' "$T/reject"
sed -i '/^USE_GSTREAMER:BOOL=ON/d' "$T/CMakeCache.txt"
if FIRE4NIX_WPE_BUILD_DIR="$T" sh "$GUARD" --check > "$T/missing"; then
  echo 'FAIL: accepted missing cache toggle' >&2; exit 1
fi
grep -q '^CACHE_MISSING=USE_GSTREAMER$' "$T/missing"
FIRE4NIX_WPE_BUILD_DIR="$T" FIRE4NIX_MEDIA_PROFILE=full sh "$GUARD" --check |
  grep -q 'PROFILE=FULL_MEDIA_OPT_IN'
if FIRE4NIX_WPE_BUILD_DIR="$T/does-not-exist" sh "$GUARD" --check > /dev/null 2>&1; then
  echo 'FAIL: passed without CMakeCache' >&2; exit 1
fi
echo 'PASS: media-free CMake cache gate rejects GStreamer ON, missing flags and unconfigured builds'
