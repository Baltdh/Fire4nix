#!/usr/bin/env bash
# Negative/positive WPE CMake configure diagnostic against *real target SDK*.
# Do not label a diagnosed missing dependency as a finished WebKit build.
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && "$(id -u)" != 0 && -n "${GITHUB_WORKSPACE:-}" ]] ||
  { echo 'ERROR: non-root CI only; never execute on the R36H' >&2; exit 4; }
base="$GITHUB_WORKSPACE"
sdk="$base/rocknix-source/build.ROCKNIX-RK3326.aarch64/toolchain"
sysroot="$sdk/aarch64-rocknix-linux-gnu/sysroot"
work="$base/wpe-post-harfbuzz-probe"
stage="$work/private-target-stage"
[[ ! -e "$work" && ! -L "$work" ]] || { echo 'ERROR: refusing existing work directory' >&2; exit 4; }
mkdir -p "$work"/{source,report,configure}
# Input artifact run IDs are fixed in CI, never borrow Ubuntu target libraries.
python3 "$base/fire4nix/scripts/assemble-wpe-post-harfbuzz-stage.py" \
  "$stage" \
  "$base/eight-artifact/eight-deps/stage" \
  "$base/fontconfig-artifact/fontconfig-target/stage" \
  "$base/cairo-artifact/cairo-target/stage" \
  "$base/icu-artifact/icu74-target/stage" \
  "$base/harfbuzz-artifact/harfbuzz-icu-target/stage" \
  "$base/glvnd-artifact/glvnd-target/stage" \
  "$base/epoxy-artifact/libepoxy-target/stage" \
  "$base/gcrypt-artifact/gcrypt-target/stage" \
  "$base/soup3-artifact/soup3-target/output" \
  "$base/soup-prereqs-artifact/soup-prereqs-target/stage" \
  "$base/xkb-artifact/xkbcommon-target/stage" \
  "$base/webp-artifact/eight-rocknix-stage" \
  "$base/libxslt-artifact/libxslt-target/stage" \
  | tee "$work/report/merge.txt"
grep -Fxq 'WPE_HARFBUZZ_ICU_EPOXY_EGL_GCRYPT_SOUP3_STAGE=PASS_REAL_ROCKNIX_AARCH64_COLLISION_SAFE' "$work/report/merge.txt"
grep -Fxq 'WPE_XKBCOMMON_WAYLAND_STAGE=PASS_REAL_ROCKNIX_AARCH64_COLLISION_SAFE' "$work/report/merge.txt"
grep -Fxq 'WPE_WEBP_DEMUX_MUX_STAGE=PASS_REAL_ROCKNIX_AARCH64_COLLISION_SAFE' "$work/report/merge.txt"
grep -Fxq 'WPE_LIBXSLT_STAGE=PASS_REAL_ROCKNIX_AARCH64_COLLISION_SAFE' "$work/report/merge.txt"
[[ "$(git -C "$base/rocknix-source" rev-parse HEAD)" == 3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb ]] || exit 4
[[ "$("$sdk/bin/aarch64-rocknix-linux-gnu-gcc" -dumpmachine)" == aarch64-rocknix-linux-gnu ]] || exit 4
readelf -h "$sysroot/usr/lib/libc.so.6" | grep -Eq 'Machine:.*AArch64'
[[ -s "$sdk/fire4nix-toolchain.cmake" ]] || exit 4
grep -Fq "$sdk" "$sdk/fire4nix-toolchain.cmake" || exit 4
# WebKit FindHarfBuzz.cmake may locate the .pc version but fail to find the
# linker alias after the GitHub Actions artifact ZIP dereferences symlinks.
# Pin only *audited actual AArch64* SONAME and headers, not host libraries.
[[ -s "$stage/usr/lib/libharfbuzz.so.0" && -s "$stage/usr/lib/libharfbuzz-icu.so.0" && -s "$stage/usr/include/harfbuzz/hb-icu.h" ]] || {
  echo 'ERROR: actual staged HarfBuzz target library/header absent' >&2; exit 5;
}
readelf -h "$stage/usr/lib/libharfbuzz.so.0" | grep -Eq 'Machine:.*AArch64' || exit 5
for pc in libxslt libwebp libwebpdemux libwebpmux xkbcommon xkbregistry wayland-client libnghttp2 libpsl libsoup-3.0 libgcrypt gpg-error harfbuzz harfbuzz-icu icu-uc icu-i18n epoxy egl glesv2 cairo fontconfig freetype2 glib-2.0 gio-2.0 gobject-2.0 libjpeg libpng16 sqlite3; do
  [[ -s "$stage/usr/lib/pkgconfig/$pc.pc" ]] ||
     { echo "ERROR: real target pkg-config stage missing $pc" >&2; exit 4; }
done
cat > "$work/report/status.txt" <<EOF
ROCKNIX_REAL_SDK_AARCH64=PASS
ROCKNIX_SOURCE_SHA=3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb
ROCKNIX_TARGET_GLIBC=2.41
TARGET_STAGE_RUN_IDS=39683307528,39687860420,39688962028,39688837904,39692709765,39692039643,39692741218,39694338119,39695603819,39695182915,39697406436,39683707451,39683799673
WPE_SOURCE_VERSION=2.54.1
WPE_MEDIA_PROFILE=GSTREAMER_OFF
WPE_WEBKIT_BUILT=no
TARGET_EXECUTED=no
R36H_INSTALLABLE=no
EOF
export PKG_CONFIG_PATH=''
export PKG_CONFIG_LIBDIR="$stage/usr/lib/pkgconfig:$sysroot/usr/lib/pkgconfig:$sysroot/usr/share/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$stage"
for pc in libnghttp2 libpsl libsoup-3.0 libgcrypt gpg-error harfbuzz harfbuzz-icu icu-uc icu-i18n epoxy egl glesv2 cairo fontconfig freetype2 glib-2.0 gio-2.0 gobject-2.0 libjpeg libpng16 sqlite3; do
  pkg-config --modversion "$pc" | awk -v name="$pc" '{print "TARGET_PC_" name "=" $0}'
done | tee "$work/report/target-package-versions.txt"
# Audit the full libsoup3 pkg-config Requires chain before CMake.
# pkg-config --modversion alone may read the version while required modules
# cannot resolve. This catches missing target metadata without host fallback.
{
  echo SOUP3_PC_PATH=\"$(pkg-config --variable=pcfiledir libsoup-3.0)\"
  echo 'SOUP3_PC_CONTENT_BEGIN'
  cat "$stage/usr/lib/pkgconfig/libsoup-3.0.pc"
  echo 'SOUP3_PC_CONTENT_END'
  if pkg-config --print-errors --exists 'libsoup-3.0 >= 3.0'; then
    echo 'SOUP3_PKGCONFIG_FULL_REQUIRES=PASS'
    pkg-config --cflags libsoup-3.0
    pkg-config --libs libsoup-3.0
  else
    echo 'SOUP3_PKGCONFIG_FULL_REQUIRES=BLOCKED'
    pkg-config --print-errors --exists 'libsoup-3.0 >= 3.0' || true
  fi
} 2>&1 | tee "$work/report/soup3-pkgconfig-resolution.txt"
# Extend rather than replace the immutable SDK toolchain: this makes CMake
# find target libraries from the downloaded private stage ahead of base libc.
cat > "$work/probe-toolchain.cmake" <<EOF
include("$sdk/fire4nix-toolchain.cmake")
list(PREPEND CMAKE_FIND_ROOT_PATH "$stage")
string(APPEND CMAKE_C_FLAGS_INIT " -I$stage/usr/include")
string(APPEND CMAKE_CXX_FLAGS_INIT " -I$stage/usr/include")
set(CMAKE_EXE_LINKER_FLAGS_INIT "-L$stage/usr/lib -Wl,-rpath-link,$stage/usr/lib")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "-L$stage/usr/lib -Wl,-rpath-link,$stage/usr/lib")
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
EOF
archive="$work/wpewebkit-2.54.1.tar.xz"
curl --fail --location --silent --show-error --retry 2 \
  --proto '=https' --proto-redir '=https' \
  --connect-timeout 15 --max-time 180 \
  'https://wpewebkit.org/releases/wpewebkit-2.54.1.tar.xz' --output "$archive"
echo "0de8bdfba011f9cd63ba9a9171fa6038dd2c08237894f4082abbb821f29d3fe9  $archive" |
  sha256sum --check
tar -xJf "$archive" -C "$work/source" --strip-components=1
[[ -s "$work/source/CMakeLists.txt" && -s "$work/source/Source/cmake/OptionsWPE.cmake" ]] ||
  { echo 'ERROR: official WPE tree incomplete' >&2; exit 6; }
echo 'WPE_SOURCE_SHA256=PASS_OFFICIAL_2_54_1' >> "$work/report/status.txt"
# This is explicitly a CONFIGURE ONLY (never cmake --build / cmake --install).
set +e
# Host wayland-protocols XML files are generator inputs; target Wayland
# libraries/headers stay in the pinned ROCKNIX sysroot.
host_protocols=/usr/share/wayland-protocols
host_scanner=$(command -v wayland-scanner) || {
 echo 'ERROR: host wayland-scanner missing' >&2; exit 26;
}
case "$host_scanner" in /usr/bin/wayland-scanner|/bin/wayland-scanner) ;; *) echo "ERROR: unapproved scanner $host_scanner" >&2; exit 26;; esac
for xml in stable/xdg-shell/xdg-shell.xml unstable/text-input/text-input-unstable-v3.xml unstable/linux-dmabuf/linux-dmabuf-unstable-v1.xml;do
 test -s "$host_protocols/$xml" || { echo "ERROR: missing host protocol $xml" >&2; exit 26; }
done
# Unifdef is a build-host code-preprocessing tool, never a target ELF.
command -v unifdef >/dev/null || {
  echo 'ERROR: missing host-side unifdef required by WPE CMake' >&2
  exit 25
}
host_unifdef=$(command -v unifdef)
case "$host_unifdef" in
  /usr/bin/unifdef|/bin/unifdef) ;;
  *) echo "ERROR: unexpected host unifdef location $host_unifdef" >&2; exit 25 ;;
esac
cmake -S "$work/source" -B "$work/configure" -G Ninja \
 -DCMAKE_TOOLCHAIN_FILE="$work/probe-toolchain.cmake" \
 -DHarfBuzz_LIBRARY:FILEPATH="$stage/usr/lib/libharfbuzz.so.0" \
 -DHarfBuzz_INCLUDE_DIR:PATH="$stage/usr/include/harfbuzz" \
 -DHarfBuzz_ICU_LIBRARY:FILEPATH="$stage/usr/lib/libharfbuzz-icu.so.0" \
 -DHarfBuzz_ICU_INCLUDE_DIR:PATH="$stage/usr/include/harfbuzz" \
 -DICU_INCLUDE_DIR:PATH="$stage/usr/include" \
 -DICU_UC_LIBRARY:FILEPATH="$stage/usr/lib/libicuuc.so.74" \
 -DICU_I18N_LIBRARY:FILEPATH="$stage/usr/lib/libicui18n.so.74" \
 -DICU_DATA_LIBRARY:FILEPATH="$stage/usr/lib/libicudata.so.74" \
 -DEpoxy_LIBRARY:FILEPATH="$stage/usr/lib/libepoxy.so.0" \
 -DEpoxy_INCLUDE_DIR:PATH="$stage/usr/include" \
 -DLibGcrypt_LIBRARY:FILEPATH="$stage/usr/lib/libgcrypt.so.20" \
 -DLibGcrypt_INCLUDE_DIR:PATH="$stage/usr/include" \
 -DLibGcrypt_GpgError_LIBRARY:FILEPATH="$stage/usr/lib/libgpg-error.so.0" \
 -DLibGcrypt_GpgError_INCLUDE_DIR:PATH="$stage/usr/include" \
 -DSoup3_LIBRARY:FILEPATH="$stage/usr/lib/libsoup-3.0.so.0" \
 -DSoup3_INCLUDE_DIR:PATH="$stage/usr/include/libsoup-3.0" \
 -DWebP_LIBRARY:FILEPATH="$stage/usr/lib/libwebp.so.7" \
 -DWebP_DEMUX_LIBRARY:FILEPATH="$stage/usr/lib/libwebpdemux.so.2" \
 -DWebP_MUX_LIBRARY:FILEPATH="$stage/usr/lib/libwebpmux.so.3" \
 -DWebP_INCLUDE_DIR:PATH="$stage/usr/include" \
 -DLIBXSLT_LIBRARY:FILEPATH="$stage/usr/lib/libxslt.so.1" \
 -DLIBXSLT_INCLUDE_DIR:PATH="$stage/usr/include" \
 -DPKG_CONFIG_USE_CMAKE_PREFIX_PATH:BOOL=OFF \
 -DUNIFDEF_EXECUTABLE:FILEPATH="$host_unifdef" \
 -DWAYLAND_PROTOCOLS_DATADIR:PATH="$host_protocols" \
 -DWAYLAND_SCANNER:FILEPATH="$host_scanner" \
 -DPORT=WPE -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr \
 -DENABLE_WPE_PLATFORM=ON -DENABLE_WPE_PLATFORM_WAYLAND=ON \
 -DENABLE_WPE_PLATFORM_HEADLESS=ON -DENABLE_WPE_PLATFORM_DRM=OFF \
 -DUSE_LIBDRM=OFF -DUSE_GBM=OFF -DENABLE_GPU_PROCESS=OFF \
 -DENABLE_WPE_LEGACY_API=OFF -DENABLE_INTROSPECTION=OFF \
 -DENABLE_DOCUMENTATION=OFF -DENABLE_SPELLCHECK=OFF \
 -DENABLE_GAMEPAD=OFF -DENABLE_BUBBLEWRAP_SANDBOX=OFF \
 -DUSE_GSTREAMER=OFF -DUSE_GSTREAMER_GL=OFF \
 -DENABLE_VIDEO=OFF -DENABLE_WEB_AUDIO=OFF \
 -DENABLE_SPEECH_SYNTHESIS=OFF -DENABLE_WEB_CODECS=OFF \
 -DENABLE_MEDIA_STREAM=OFF -DENABLE_WEB_RTC=OFF \
 -DENABLE_MEDIA_RECORDER=OFF -DUSE_AVIF=OFF \
 -DUSE_JPEGXL=OFF -DUSE_WOFF2=OFF -DUSE_ATK=OFF \
 -DUSE_LIBHYPHEN=OFF -DENABLE_JOURNALD_LOG=OFF \
 -DUSE_LCMS=OFF -DUSE_LIBBACKTRACE=OFF \
 -DUSE_SYSTEM_SYSPROF_CAPTURE=OFF -DUSE_SYSPROF_CAPTURE=OFF \
 -DENABLE_AV1=OFF -DENABLE_WEBDRIVER=OFF \
 > "$work/report/cmake.log" 2>&1
rc=$?
set -e
echo "WPE_CMAKE_EXIT_CODE=$rc" >> "$work/report/status.txt"
# Document an opt-in REDUCED profile: this is not a replacement for the
# DRM/GBM-enabled ROCKNIX graphical build. It only isolates the requirements
# for the WPEPlatform Wayland client in a first-HTML configuration.
cache="$work/configure/CMakeCache.txt"
for option in USE_LIBDRM USE_GBM ENABLE_GPU_PROCESS ENABLE_WPE_PLATFORM_DRM;do
  grep -Eq "^$option:BOOL=OFF$" "$cache" || {
    echo "ERROR: CMake did not retain $option=OFF; reduced-profile probe invalid" >&2
    exit 24
  }
done
if grep -q 'libdrm is required for USE_LIBDRM' "$work/report/cmake.log";then
  echo 'ERROR: CMake still entered DRM-enabled path with explicit OFF profile' >&2
  exit 24
fi
echo 'WPE_REDUCED_WAYLAND_NO_DRM_GBM=PASS_CMAKE_CACHE_GATED' | tee -a "$work/report/status.txt"
if [ "$rc" -eq 0 ]; then
  # Only label *configure* complete after confirming our media-free cache.
  FIRE4NIX_WPE_BUILD_DIR="$work/configure" FIRE4NIX_MEDIA_PROFILE=minimal \
    sh "$base/fire4nix/rocknix-integration/verify-wpe-media-cache.sh" --check \
    > "$work/report/media-gate.txt" 2>&1 || {
      echo 'ERROR: CMake configured but media-free profile not verified' >&2
      cat "$work/report/media-gate.txt"
      exit 7
    }
  echo 'WPE_TARGET_CONFIGURE=CONFIGURED_REQUIRES_ABI_REVIEW' | tee -a "$work/report/status.txt"
else
  # Failing configure is an EXPECTED diagnostic, not a successful build.
  # Preserve full log and classify the actual reason without hiding errors.
  if ! grep -Eq 'CMake Error|Could NOT find|Could not find|Configuring incomplete|required package' "$work/report/cmake.log"; then
    echo 'ERROR: unexpected CMake configure failure; read full logs' >&2
    tail -n 90 "$work/report/cmake.log"
    exit 8
  fi
  echo 'WPE_TARGET_CONFIGURE=BLOCKED_WITH_REAL_SDK' | tee -a "$work/report/status.txt"
  grep -E -A 8 'CMake Error|Could NOT find|Could not find|required package' "$work/report/cmake.log" |
    head -n 160 > "$work/report/first-errors.txt" || true
  echo 'WPE_FIRST_CMAKE_BLOCKERS_BEGIN'
  cat "$work/report/first-errors.txt"
  echo 'WPE_FIRST_CMAKE_BLOCKERS_END'
fi
if grep -Eq 'CMake Error at .*FindHarfBuzz.cmake|Could NOT find HarfBuzz|_HarfBuzz_REQUIRED_LIBS_FOUND|Required version \(2\.7\.4\).*found version' "$work/report/cmake.log"; then
  echo 'HARFBUZZ_ICU_FIRST_BLOCKER_CLEARED=NO' | tee -a "$work/report/status.txt"
  echo 'ERROR: WPE still cannot find genuine HarfBuzz after staged target build' >&2
  exit 18
fi
echo 'HARFBUZZ_ICU_FIRST_BLOCKER_CLEARED=YES' | tee -a "$work/report/status.txt"
if grep -Eq 'Could NOT find LibGcrypt|LibGcrypt_(GpgError_)?(LIBRARY|INCLUDE_DIR)' "$work/report/cmake.log"; then
  echo 'LIBGCRYPT_FIRST_BLOCKER_CLEARED=NO' | tee -a "$work/report/status.txt"
  echo 'ERROR: LibGcrypt/GpgError are not resolved for WPE yet' >&2
  exit 19
fi
echo 'LIBGCRYPT_FIRST_BLOCKER_CLEARED=YES' | tee -a "$work/report/status.txt"
if grep -Eq 'Could NOT find Soup3|Soup3_(LIBRARY|INCLUDE_DIR)' "$work/report/cmake.log"; then
  echo 'SOUP3_FIRST_BLOCKER_CLEARED=NO' | tee -a "$work/report/status.txt"
  echo 'ERROR: WPE still cannot find genuine Soup3 after staged target build' >&2
  exit 20
fi
echo 'SOUP3_FIRST_BLOCKER_CLEARED=YES' | tee -a "$work/report/status.txt"
if grep -Eq 'Could NOT find XkbCommon|XkbCommon_VERSION|XkbCommon_PKG_CONFIG_SPEC' "$work/report/cmake.log";then
  echo 'XKBCOMMON_FIRST_BLOCKER_CLEARED=NO' | tee -a "$work/report/status.txt"
  echo 'ERROR: WPE still cannot detect genuine target XkbCommon package metadata' >&2
  exit 21
fi
echo 'XKBCOMMON_FIRST_BLOCKER_CLEARED=YES' | tee -a "$work/report/status.txt"
if ! pkg-config --exists 'xkbcommon >= 1.6.0' || ! pkg-config --exists 'wayland-client >= 1.23.1';then
  echo 'ERROR: target XkbCommon/Wayland pkg-config requirements not satisfied' >&2
  exit 21
fi
if grep -Eq 'Could NOT find WebP|WebP_(INCLUDE_DIR|LIBRARY|DEMUX_LIBRARY|MUX_LIBRARY)|_WebP_REQUIRED_LIBS_FOUND' "$work/report/cmake.log";then
  echo 'WEBP_FIRST_BLOCKER_CLEARED=NO' | tee -a "$work/report/status.txt"
  echo 'ERROR: WPE still cannot resolve genuine WebP/demux/mux target libraries' >&2
  exit 22
fi
echo 'WEBP_FIRST_BLOCKER_CLEARED=YES' | tee -a "$work/report/status.txt"
if ! pkg-config --exists 'libwebp >= 1.6.0' || ! pkg-config --exists libwebpdemux || ! pkg-config --exists libwebpmux;then
  echo 'ERROR: WebP target metadata/dependencies incomplete' >&2
  exit 22
fi
if grep -Eq 'Could NOT find LibXslt|LIBXSLT_(LIBRARIES|INCLUDE_DIR)' "$work/report/cmake.log";then
  echo 'LIBXSLT_FIRST_BLOCKER_CLEARED=NO' | tee -a "$work/report/status.txt"
  echo 'ERROR: WPE cannot resolve genuine LibXslt target shared ELF/includes' >&2
  exit 23
fi
echo 'LIBXSLT_FIRST_BLOCKER_CLEARED=YES' | tee -a "$work/report/status.txt"
if ! pkg-config --exists 'libxslt >= 1.1.13';then
  echo 'ERROR: target LibXslt development metadata unavailable' >&2
  exit 23
fi
echo 'NO_FIRMWARE_WRITES=YES' >> "$work/report/status.txt"
echo 'WPE_CONFIGURE_PROBE=RECORDED_NO_DRM_GBM_LIBXSLT_WEBP_XKB_WAYLAND_SOUP3_GCRYPT_GPGERROR_HARFBUZZ_ICU_EPOXY_EGL_TARGET_SDK' >> "$work/report/status.txt"
cat "$work/report/status.txt"
