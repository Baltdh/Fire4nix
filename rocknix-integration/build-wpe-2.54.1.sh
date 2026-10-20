#!/bin/sh
# Fire4Nix: reproducible WPE 2.54.1 *source build* preparation for ROCKNIX.
# No downloads, apt operations, root privileges, or changes to the SD card.
set -eu

VERSION=2.54.1
SOURCE_SHA256=0de8bdfba011f9cd63ba9a9171fa6038dd2c08237894f4082abbb821f29d3fe9
mode=${1:---plan}
case "$mode" in
  --plan|--preflight|--probe-compiler|--configure|--build|--stage) ;;
  *) echo "Usage: $0 [--plan|--preflight|--probe-compiler|--configure|--build|--stage]" >&2; exit 2 ;;
esac

# Match the device rootfs, not just the CPU. The tested R36H reports glibc 2.41,
# matching ROCKNIX 20260801, whereas 20261001 recipes require glibc 2.44.
# Using the host compiler is NOT a valid R36H build.
RELEASE=${FIRE4NIX_ROCKNIX_RELEASE:-20260801}
case "$RELEASE" in 20260801|20261001) ;; *) echo 'ERROR: unsupported ROCKNIX release; use an audited SDK' >&2; exit 4 ;; esac
MEDIA_PROFILE=${FIRE4NIX_MEDIA_PROFILE:-minimal}
case "$MEDIA_PROFILE" in minimal|full) ;; *) echo 'ERROR: media profile must be minimal or full' >&2; exit 4 ;; esac
TARGET_GLIBC=2.41
[ "$RELEASE" != 20261001 ] || TARGET_GLIBC=2.44
ARCHIVE=${FIRE4NIX_WPE_ARCHIVE:-}
TOOLCHAIN=${FIRE4NIX_ROCKNIX_TOOLCHAIN:-}
WORK=${FIRE4NIX_WPE_WORK:-./build-wpe-2541-rk3326}
SOURCE="$WORK/src"
BUILD="$WORK/build"

echo "source=wpewebkit-$VERSION.tar.xz"
echo "sha256=$SOURCE_SHA256"
echo "target=ROCKNIX-$RELEASE-aarch64-cortex-a35"
echo "target_glibc_recipe=$TARGET_GLIBC"
echo "media_profile=$MEDIA_PROFILE"
if [ "$MEDIA_PROFILE" = minimal ]; then
  echo "media_policy=disable_GStreamer_video_audio_speech_WebCodecs_for_first_browser"
else
  echo "media_policy=full_requires_coherent_GStreamer_toolchain_and_ABI_check"
fi
echo "device_observed_glibc=2.41"
if [ "$RELEASE" != 20260801 ]; then
  echo "WARNING: selected release differs from tested R36H glibc 2.41; do not deploy before ABI audit" >&2
fi
echo "backend=WPEPlatform Wayland (DRM/headless optional)"
echo "expected_runtime=libWPEWebKit-2.0.so.1 + WebKit child processes + dependencies"
echo "status=source build recipe; runtime NOT yet compiled or distributed"
if [ "$mode" = --plan ]; then
  echo 'To configure, set FIRE4NIX_WPE_ARCHIVE to the official tarball and'
  echo 'FIRE4NIX_ROCKNIX_TOOLCHAIN to a cross toolchain CMake file built'
  echo 'from the matching ROCKNIX release source environment.'
  echo 'Set FIRE4NIX_ROCKNIX_SYSROOT to its absolute sysroot directory.'
  echo 'Run --preflight to validate target libc identity before compiling.'
  echo 'Then run this script with --configure, --build and --stage.'
  echo 'Stage requires a separate ROCKNIX SDK DESTDIR and the runtime audit script.'
  echo 'No build or installation is performed by --plan.'
  exit 0
fi
[ -n "$TOOLCHAIN" ] && [ -f "$TOOLCHAIN" ] || {
  echo "ERROR: ROCKNIX cross-toolchain CMake file required; no host fallback" >&2
  exit 4
}
# Fail before CMake spends hours on a host or mismatched target sysroot.
# This is not a proof of a working toolchain or actual WPE runtime.
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 2
PREFLIGHT="$SCRIPT_DIR/check-rocknix-sdk.sh"
[ -f "$PREFLIGHT" ] || { echo 'ERROR: SDK preflight script missing beside build recipe' >&2; exit 4; }
sh "$PREFLIGHT" --check || exit 4
if [ "$mode" = --preflight ]; then
  echo 'status=SDK_IDENTITY_CHECKED_NO_BUILD'
  exit 0
fi
# Probe the actual cross compiler, not just the SDK directory it claims to use.
# The test compiles tiny C/C++ executables without running them on the host.
COMPILER_PROBE="$SCRIPT_DIR/check-rocknix-compiler.sh"
[ -f "$COMPILER_PROBE" ] || {
  echo 'ERROR: compiler preflight script missing beside WPE build recipe' >&2 >&2
  exit 4
}
sh "$COMPILER_PROBE" --check || exit 4
# The observed R36H WPE links nine GST modules. Stop if upstream CMake
# silently ignores our media-free -D options; names alone are not proof.
MEDIA_GATE="$SCRIPT_DIR/verify-wpe-media-cache.sh"
[ -f "$MEDIA_GATE" ] || { echo 'ERROR: WPE media cache verification script missing' >&2; exit 4; }
if [ "$mode" = --probe-compiler ]; then
  echo 'status=COMPILER_VERIFIED_NO_WEBKIT_BUILD'
  exit 0
fi

command -v cmake >/dev/null 2>&1 || { echo 'ERROR: cmake missing' >&2; exit 4; }
command -v ninja >/dev/null 2>&1 || { echo 'ERROR: ninja missing' >&2; exit 4; }
if [ "$mode" = --configure ]; then
  [ -n "$ARCHIVE" ] && [ -f "$ARCHIVE" ] || {
    echo 'ERROR: supply wpewebkit-2.54.1.tar.xz in FIRE4NIX_WPE_ARCHIVE' >&2
    exit 5
  }
  command -v sha256sum >/dev/null 2>&1 || exit 5
  actual=$(sha256sum "$ARCHIVE" | awk '{print $1}')
  [ "$actual" = "$SOURCE_SHA256" ] || {
    echo 'ERROR: source SHA-256 does not match the official 2.54.1 release' >&2
    exit 5
  }
  mkdir -p "$SOURCE" "$BUILD"
  tar -xf "$ARCHIVE" -C "$SOURCE" --strip-components=1
  # Options verified against WPE 2.54 stable. Conservative defaults for an
  # embedded 1GB target. Do not pull GI scanners or gi-docgen into the SDK:
  # they are build-time tooling and unnecessary for a standalone browser.
  # WPE 2.54 GStreamerDependencies.cmake binds VIDEO, WEB_AUDIO,
  # SPEECH_SYNTHESIS and WEB_CODECS to USE_GSTREAMER. Minimal browsing
  # intentionally disables these rather than supplying broken GST .so files.
  # Full profile is opt-in after rebuilding *all* GStreamer modules coherently.
  if [ "$MEDIA_PROFILE" = minimal ]; then
    set -- -DUSE_GSTREAMER=OFF -DUSE_GSTREAMER_GL=OFF \
      -DENABLE_VIDEO=OFF -DENABLE_WEB_AUDIO=OFF \
      -DENABLE_SPEECH_SYNTHESIS=OFF -DENABLE_WEB_CODECS=OFF \
      -DENABLE_MEDIA_STREAM=OFF -DENABLE_WEB_RTC=OFF \
      -DENABLE_MEDIA_RECORDER=OFF \
      -DUSE_ATK=OFF -DUSE_JPEGXL=OFF -DUSE_WOFF2=OFF \
      -DUSE_LIBHYPHEN=OFF -DUSE_AVIF=OFF \
      -DENABLE_JOURNALD_LOG=OFF -DUSE_LCMS=OFF -DUSE_LIBBACKTRACE=OFF
  else
    set -- -DUSE_GSTREAMER=ON \
      -DENABLE_VIDEO=ON -DENABLE_WEB_AUDIO=ON \
      -DENABLE_WEB_CODECS=ON -DENABLE_MEDIA_STREAM=ON
  fi
  cmake -S "$SOURCE" -B "$BUILD" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
    -DPORT=WPE \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DENABLE_WPE_PLATFORM=ON \
    -DENABLE_WPE_PLATFORM_WAYLAND=ON \
    -DENABLE_WPE_PLATFORM_HEADLESS=ON \
    -DENABLE_WPE_PLATFORM_DRM=OFF \
    -DENABLE_WPE_LEGACY_API=OFF \
    -DENABLE_SPELLCHECK=OFF \
    -DENABLE_INTROSPECTION=OFF \
    -DENABLE_DOCUMENTATION=OFF \
    "$@"
  FIRE4NIX_WPE_BUILD_DIR="$BUILD" FIRE4NIX_MEDIA_PROFILE="$MEDIA_PROFILE" \
    sh "$MEDIA_GATE" --check || {
      echo 'ERROR: CMake did not honor GStreamer-free configuration; refusing WPE build' >&2
      exit 5
    }
  # A later --build/--stage must not silently use a different media profile.
  printf '%s\n' "$MEDIA_PROFILE" > "$BUILD/fire4nix-media-profile.txt"
else
  [ -f "$BUILD/build.ninja" ] || {
    echo 'ERROR: run --configure with the ROCKNIX SDK first' >&2
    exit 5
  }
  [ -f "$BUILD/fire4nix-media-profile.txt" ] || {
    echo 'ERROR: configure again to record a verifiable media profile' >&2
    exit 5
  }
  FIRE4NIX_WPE_BUILD_DIR="$BUILD" FIRE4NIX_MEDIA_PROFILE="$MEDIA_PROFILE" \
    sh "$MEDIA_GATE" --check || {
      echo 'ERROR: cached WPE media options changed since configuration' >&2
      exit 5
    }
  configured_profile=$(cat "$BUILD/fire4nix-media-profile.txt")
  [ "$configured_profile" = "$MEDIA_PROFILE" ] || {
    echo "ERROR: configured media_profile=$configured_profile, requested=$MEDIA_PROFILE; do not mix outputs" >&2
    exit 5
  }
  if [ "$mode" = --build ]; then
    cmake --build "$BUILD" --parallel "${FIRE4NIX_BUILD_JOBS:-2}"
    echo 'Build completed; run --stage to collect candidate ARM64 WebKit binaries.'
  else
    # Never install into /usr on the build host. CMake's prefix is /usr but
    # DESTDIR relocates files into our private staging directory.
    SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 2
    STAGER="$SCRIPT_DIR/Empacotar-WPE-ROCKNIX.sh"
    [ -f "$STAGER" ] || STAGER="$SCRIPT_DIR/stage-wpe-runtime.sh"
    [ -f "$STAGER" ] || {
      echo 'ERROR: stage-wpe-runtime.sh not found beside this script' >&2
      exit 5
    }
    DESTDIR="$WORK/destdir"
    mkdir -p "$DESTDIR"
    DESTDIR="$DESTDIR" cmake --install "$BUILD"
    FIRE4NIX_REQUIRE_MEDIA_FREE=$([ "$MEDIA_PROFILE" = minimal ] && echo 1 || echo 0) \
    FIRE4NIX_TARGET_GLIBC_MAX="$TARGET_GLIBC" \
    FIRE4NIX_WPE_DESTDIR="$DESTDIR" \
      FIRE4NIX_WPE_RUNTIME_OUT="${FIRE4NIX_WPE_RUNTIME_OUT:-$WORK/fire4nix-runtime}" \
      sh "$STAGER" --stage
    echo 'WPE runtime staged; target GLIBC dependencies and actual Mali/Wayland remain to test.'
  fi
fi
