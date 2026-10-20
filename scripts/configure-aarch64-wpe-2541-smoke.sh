#!/usr/bin/env bash
# Native ARM64 CMake configure smoke: exact upstream WPE 2.54.1, no WebKit build.
# Uses isolated Ubuntu runner prerequisites; NEVER a ROCKNIX firmware package.
set -euo pipefail
[ "$(uname -m)" = aarch64 ] || { echo 'ERROR: need native AArch64 runner' >&2; exit 4; }
for app in curl tar sha256sum cmake ninja pkg-config; do
  command -v "$app" >/dev/null || { echo "ERROR: missing $app" >&2; exit 4; }
done
work=${FIRE4NIX_BUILD_WORK:-}
[ -n "$work" ] && [ -d "$work" ] || { echo 'ERROR: FIRE4NIX_BUILD_WORK required' >&2; exit 4; }
prefix="$work/arm64-prerequisites"
[ -d "$prefix/lib" ] || { echo 'ERROR: native Soup3 build not completed' >&2; exit 4; }
mkdir -p "$work/reports" "$work/wpe-src"
export PKG_CONFIG_PATH="$prefix/lib/pkgconfig:$prefix/share/pkgconfig:${PKG_CONFIG_PATH:-}"
export CMAKE_PREFIX_PATH="$prefix${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
export LD_LIBRARY_PATH="$prefix/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
archive="$work/wpewebkit-2.54.1.tar.xz"
echo 'WPE_SOURCE_DOWNLOAD=START'
curl --fail --location --retry 3 --retry-delay 2 --proto '=https' --tlsv1.2 \
   --silent --show-error https://wpewebkit.org/releases/wpewebkit-2.54.1.tar.xz -o "$archive"
printf '%s  %s\n' '0de8bdfba011f9cd63ba9a9171fa6038dd2c08237894f4082abbb821f29d3fe9' "$archive" |
  sha256sum --check --status || { echo 'ERROR: unexpected WPE source SHA-256' >&2; exit 5; }
tar -xf "$archive" -C "$work/wpe-src"
rm -f "$archive"
source="$work/wpe-src/wpewebkit-2.54.1"
[ -r "$source/CMakeLists.txt" ] || { echo 'ERROR: upstream tarball directory differs' >&2; exit 5; }
echo 'WPE_SOURCE_SHA256=PASS'
echo 'WPE_CMAKE_CONFIGURE=START'
if ! cmake -S "$source" -B "$work/wpe-cmake" -G Ninja \
  -DPORT=WPE \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/usr \
  -DENABLE_WPE_PLATFORM=ON \
  -DENABLE_WPE_PLATFORM_WAYLAND=ON \
  -DENABLE_WPE_PLATFORM_HEADLESS=ON \
  -DENABLE_WPE_PLATFORM_DRM=OFF \
  -DENABLE_WPE_LEGACY_API=OFF \
  -DENABLE_INTROSPECTION=OFF \
  -DENABLE_DOCUMENTATION=OFF \
  -DENABLE_BUBBLEWRAP_SANDBOX=OFF \
  -DENABLE_SPELLCHECK=OFF \
  -DENABLE_GAMEPAD=OFF \
  -DUSE_ATK=OFF \
  -DUSE_LIBHYPHEN=OFF \
  -DUSE_AVIF=OFF \
  -DENABLE_WEBDRIVER=OFF \
  -DUSE_GSTREAMER=OFF \
  -DUSE_GSTREAMER_GL=OFF \
  -DENABLE_VIDEO=OFF \
  -DENABLE_WEB_AUDIO=OFF \
  -DENABLE_SPEECH_SYNTHESIS=OFF \
  -DENABLE_WEB_CODECS=OFF \
  -DENABLE_MEDIA_STREAM=OFF \
  -DENABLE_WEB_RTC=OFF \
  -DENABLE_MEDIA_RECORDER=OFF \
  -DUSE_JPEGXL=OFF \
  -DUSE_WOFF2=OFF \
  -DUSE_GBM=OFF \
  -DUSE_LIBDRM=OFF \
  >"$work/reports/wpe-cmake-configure.log" 2>&1; then
    echo 'WPE_CMAKE_CONFIGURE=BLOCKED_BY_MISSING_DEPENDENCY_OR_OPTION'
    tail -n 90 "$work/reports/wpe-cmake-configure.log"
    exit 12
fi
echo 'WPE_CMAKE_CONFIGURE=PASS'
self=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
FIRE4NIX_WPE_BUILD_DIR="$work/wpe-cmake" FIRE4NIX_MEDIA_PROFILE=minimal \
  sh "$self/rocknix-integration/verify-wpe-media-cache.sh" --check \
  | tee "$work/reports/wpe-media-cache-check.txt"
echo 'WPE_CMAKE_CONFIGURED_ON_NATIVE_UBUNTU_ARM64=YES'
echo 'WPE_FULL_BUILD_COMPLETED=NO'
echo 'ROCKNIX_SDK_MATCHED=NO'
echo 'WPE_RUNTIME_CAN_DEPLOY_ON_R36H=NO'
