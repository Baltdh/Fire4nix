#!/bin/sh
# Fire4Nix WPE 2.54.1: verify CMake actually honored media-free settings.
# This does not build/execute WPE or modify any ROCKNIX storage.
set -eu
case "${1:---check}" in
  --check) ;;
  --help) echo 'FIRE4NIX_WPE_BUILD_DIR=/path/to/build sh verify-wpe-media-cache.sh --check'; exit 0 ;;
  *) echo 'ERROR: supported option is --check' >&2; exit 2 ;;
esac
dir=${FIRE4NIX_WPE_BUILD_DIR:-}
[ -n "$dir" ] && [ -f "$dir/CMakeCache.txt" ] || {
  echo 'ERROR: CMakeCache.txt missing; configure the actual WPE SDK build first' >&2
  exit 5
}
profile=${FIRE4NIX_MEDIA_PROFILE:-minimal}
case "$profile" in
  minimal) ;;
  full) echo 'PROFILE=FULL_MEDIA_OPT_IN; no GStreamer-free guarantee'; exit 0 ;;
  *) echo 'ERROR: unknown media profile' >&2; exit 4 ;;
esac
# Require cache entries for the exact upstream WPE 2.54.1 toggles.
# A CMake command-line -D alone is not proof that a port accepted its value.
awk -F= '
  function assert_bool(key, want,   actual, expected) {
    expected=want
    if (!(key in value)) {
      print "CACHE_MISSING=" key
      bad++
      return
    }
    actual=toupper(value[key])
    if ((want=="ON" && actual!="ON" && actual!="TRUE" && actual!="1") ||
        (want=="OFF" && actual!="OFF" && actual!="FALSE" && actual!="0")) {
      print "CACHE_WRONG=" key " actual=" actual " expected=" expected
      bad++
    }
  }
  /^[A-Za-z_][A-Za-z0-9_]*:[A-Za-z_]+=/ {
    split($1, name, ":")
    value[name[1]]=$2
  }
  END {
    assert_bool("ENABLE_WPE_PLATFORM", "ON")
    assert_bool("ENABLE_WPE_PLATFORM_WAYLAND", "ON")
    assert_bool("ENABLE_WPE_LEGACY_API", "OFF")
    assert_bool("USE_GSTREAMER", "OFF")
    assert_bool("USE_GSTREAMER_GL", "OFF")
    assert_bool("ENABLE_VIDEO", "OFF")
    assert_bool("ENABLE_WEB_AUDIO", "OFF")
    assert_bool("ENABLE_SPEECH_SYNTHESIS", "OFF")
    assert_bool("ENABLE_WEB_CODECS", "OFF")
    assert_bool("ENABLE_MEDIA_STREAM", "OFF")
    assert_bool("ENABLE_WEB_RTC", "OFF")
    assert_bool("ENABLE_MEDIA_RECORDER", "OFF")
    assert_bool("ENABLE_INTROSPECTION", "OFF")
    assert_bool("ENABLE_DOCUMENTATION", "OFF")
    if (bad) {
      print "MEDIA_CACHE_STATUS=BLOCKED mismatches=" bad
      exit 6
    }
    print "MEDIA_CACHE_STATUS=PASS_WPE_WAYLAND_WITHOUT_GSTREAMER"
    print "note=only_configuration_checked_runtime_DT_NEEDED_is_checked_during_staging"
  }
' "$dir/CMakeCache.txt"
