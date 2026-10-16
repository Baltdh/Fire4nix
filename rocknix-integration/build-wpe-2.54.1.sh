#!/bin/sh
# Fire4Nix: reproducible WPE 2.54.1 *source build* preparation for ROCKNIX.
# No downloads, apt operations, root privileges, or changes to the SD card.
set -eu

VERSION=2.54.1
SOURCE_SHA256=0de8bdfba011f9cd63ba9a9171fa6038dd2c08237894f4082abbb821f29d3fe9
mode=${1:---plan}
case "$mode" in
  --plan|--configure|--build|--stage) ;;
  *) echo "Usage: $0 [--plan|--configure|--build|--stage]" >&2; exit 2 ;;
esac

# Point these at the *actual ROCKNIX 20261001 cross-build SDK*.
# Using the host compiler is NOT a valid R36H build.
ARCHIVE=${FIRE4NIX_WPE_ARCHIVE:-}
TOOLCHAIN=${FIRE4NIX_ROCKNIX_TOOLCHAIN:-}
WORK=${FIRE4NIX_WPE_WORK:-./build-wpe-2541-rk3326}
SOURCE="$WORK/src"
BUILD="$WORK/build"

echo "source=wpewebkit-$VERSION.tar.xz"
echo "sha256=$SOURCE_SHA256"
echo "target=ROCKNIX-20261001-aarch64-cortex-a35"
echo "backend=WPEPlatform Wayland (DRM/headless optional)"
echo "expected_runtime=libWPEWebKit-2.0.so.1 + WebKit child processes + dependencies"
echo "status=source build recipe; runtime NOT yet compiled or distributed"
if [ "$mode" = --plan ]; then
  echo 'To configure, set FIRE4NIX_WPE_ARCHIVE to the official tarball and'
  echo 'FIRE4NIX_ROCKNIX_TOOLCHAIN to a cross toolchain CMake file built'
  echo 'from the ROCKNIX 20261001 source environment.'
  echo 'Then run this script with --configure, --build and --stage.'
  echo 'Stage requires a separate ROCKNIX SDK DESTDIR and the runtime audit script.'
  echo 'No build or installation is performed by --plan.'
  exit 0
fi
[ -n "$TOOLCHAIN" ] && [ -f "$TOOLCHAIN" ] || {
  echo "ERROR: ROCKNIX cross-toolchain CMake file required; no host fallback" >&2
  exit 4
}
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
  # These options exist in WebKit Source/cmake/OptionsWPE.cmake on
  # the webkitglib/2.54 branch. Conservative features for a 1GB device.
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
    -DENABLE_WEB_AUDIO=OFF \
    -DENABLE_VIDEO=OFF
else
  [ -f "$BUILD/build.ninja" ] || {
    echo 'ERROR: run --configure with the ROCKNIX SDK first' >&2
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
    FIRE4NIX_WPE_DESTDIR="$DESTDIR" \
      FIRE4NIX_WPE_RUNTIME_OUT="${FIRE4NIX_WPE_RUNTIME_OUT:-$WORK/fire4nix-runtime}" \
      sh "$STAGER" --stage
    echo 'WPE runtime staged; target GLIBC dependencies and actual Mali/Wayland remain to test.'
  fi
fi
