#!/usr/bin/env bash
# Verify real WPE 2.54.1 CMake configuration from consolidated ROCKNIX SDK.
# Do not label a diagnosed missing dependency as a finished WebKit build.
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && "$(id -u)" != 0 && -n "${GITHUB_WORKSPACE:-}" ]] ||
  { echo 'ERROR: non-root CI only; never execute on the R36H' >&2; exit 4; }
base="$GITHUB_WORKSPACE"
sdk="$base/rocknix-source/build.ROCKNIX-RK3326.aarch64/toolchain"
sysroot="$sdk/aarch64-rocknix-linux-gnu/sysroot"
work="$base/wpe-unified-sdk-build"
stage="$base/stage1-artifact/stage1-combined"
[[ ! -e "$work" && ! -L "$work" ]] || { echo 'ERROR: refusing existing work directory' >&2; exit 4; }
mkdir -p "$work"/{source,report,configure}
# Immutable stage-1 artifact (CI 39706017583) has already merged 15 real
# ROCKNIX target inputs and verified 22/22 development package metadata.
# Do NOT merge or inject host libraries into this stage.
[[ -s "$base/stage1-artifact/stage1-reports/pkgconfig-readiness.txt" ]] || {
 echo 'ERROR: missing authenticated stage-1 audit' >&2; exit 5;
}
grep -Fxq 'TARGET_PC_MISSING_COUNT=0' "$base/stage1-artifact/stage1-reports/pkgconfig-readiness.txt"
grep -Fxq 'SYSROOT_PC_AUDIT=PASS_TARGET_PKGCONFIG_METADATA_ONLY' "$base/stage1-artifact/stage1-reports/pkgconfig-readiness.txt"
[[ -d "$stage/usr/lib" && -d "$stage/usr/include" ]] || {
 echo 'ERROR: stage-1 target library or include tree missing' >&2; exit 5;
}
grep -Fxq 'STAGE1_ROCKNIX_COMBINED=PASS_REAL_ELF64_AARCH64_COLLISION_SAFE' "$base/stage1-artifact/stage1-reports/merge.txt"
echo 'UNIFIED_ROCKNIX_SDK=PASS_STAGE1_15_ARTIFACTS' | tee "$work/report/merge.txt"
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
TARGET_STAGE_RUN_ID=39706017583
WPE_SOURCE_VERSION=2.54.1
WPE_MEDIA_PROFILE=GSTREAMER_OFF
WPE_WEBKIT_BUILT=no
TARGET_EXECUTED=no
R36H_INSTALLABLE=no
EOF
export PKG_CONFIG_PATH=''
export PKG_CONFIG_LIBDIR="$stage/usr/lib/pkgconfig:$stage/usr/share/pkgconfig:$sysroot/usr/lib/pkgconfig:$sysroot/usr/share/pkgconfig"
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
# The first genuine WPE 2.54.1 GCC15 build (#39893792106) reached
# [8830/8833] and linked libWPEWebKit but failed WPEWebProcess because ld
# could not locate libatomic.so.1 for __atomic_load_16/__atomic_store_16.
# ROCKNIX GCC 15.2 resolves it in aarch64-rocknix-linux-gnu/lib64, which is
# NOT part of the stage1 pkg-config library search directory.
atomic_path=$("$sdk/bin/aarch64-rocknix-linux-gnu-gcc" -print-file-name=libatomic.so.1)
[[ -f "$atomic_path" ]] || { echo 'ERROR: ROCKNIX target libatomic.so.1 missing' >&2; exit 32; }
atomic_path=$(realpath -e "$atomic_path") || exit 32
case "$atomic_path" in "$sdk"/aarch64-rocknix-linux-gnu/lib64/*) ;; *)
  echo "ERROR: libatomic resolved outside pinned ROCKNIX target GCC lib64: $atomic_path" >&2
  exit 32
esac
atomic_dir=$(dirname "$atomic_path")
readelf -h "$atomic_path" | grep -Eq 'Machine:[[:space:]]+AArch64' || exit 32
readelf -d "$atomic_path" | grep -Fq '[libatomic.so.1]' || exit 32
readelf --wide --dyn-syms "$atomic_path" | grep -Fq '__atomic_load_16' || exit 32
readelf --wide --dyn-syms "$atomic_path" | grep -Fq '__atomic_store_16' || exit 32
python3 - "$atomic_path" <<'PY'
import re, subprocess, sys
out=subprocess.check_output(["readelf","--wide","-V",sys.argv[1]],text=True)
if any((int(a),int(b))>(2,41) for a,b in re.findall(r"Name:\s*GLIBC_(\d+)\.(\d+)",out)):
    raise SystemExit("ERROR: ROCKNIX libatomic requires GLIBC newer than 2.41")
PY
echo 'WPE_ROCKNIX_LIBATOMIC16=PASS_PINNED_GCC_TARGET_LIB64' >> "$work/report/status.txt"
echo 'WPE_ROCKNIX_LIBATOMIC16_LINKER=RPATH_LINK_ONLY_NOT_EMBEDDED_RUNPATH' >> "$work/report/status.txt"

# Extend rather than replace the immutable SDK toolchain: this makes CMake
# find target libraries from the downloaded private stage ahead of base libc.
cat > "$work/probe-toolchain.cmake" <<EOF
include("$sdk/fire4nix-toolchain.cmake")
list(PREPEND CMAKE_FIND_ROOT_PATH "$stage")
# GCC15 ROCKNIX AArch64 emits unresolved __aarch64_ldadd/cas/swp
# outline helpers without this target-specific flag. Use ARMv8.0 inline
# LL/SC atomics in C and C++ across WebKit, ANGLE and subprocesses.
string(APPEND CMAKE_C_FLAGS_INIT " -I$stage/usr/include -mno-outline-atomics")
string(APPEND CMAKE_CXX_FLAGS_INIT " -I$stage/usr/include -mno-outline-atomics")
set(CMAKE_EXE_LINKER_FLAGS_INIT "-L$stage/usr/lib -Wl,-rpath-link,$stage/usr/lib -Wl,-rpath-link,$atomic_dir")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "-L$stage/usr/lib -Wl,-rpath-link,$stage/usr/lib -Wl,-rpath-link,$atomic_dir")
set(CMAKE_MODULE_LINKER_FLAGS_INIT "-L$stage/usr/lib -Wl,-rpath-link,$stage/usr/lib -Wl,-rpath-link,$atomic_dir")
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
# Extracted copy only: WPE snapshot uses DRM_FORMAT_XRGB8888 while
# USE_LIBDRM=OFF, making the name undefined. Preserve pinned upstream archive.
python3 "$base/fire4nix/scripts/patch-wpe2541-drm-fourcc.py" \
 --source-root "$work/source" \
 --report "$work/report/wpe2541-fourcc-patch.txt"
grep -Fxq 'WPE_SOURCE_PATCH=WPE2541_WPE_SNAPSHOT_FOURCC_NO_LIBDRM_V1' \
 "$work/report/wpe2541-fourcc-patch.txt" || exit 30
echo 'WPE_SOURCE_PATCH=WPE2541_WPE_SNAPSHOT_FOURCC_NO_LIBDRM_V1' >> "$work/report/status.txt"
echo 'WPE_SOURCE_SHA256=PASS_OFFICIAL_2_54_1' >> "$work/report/status.txt"
# Explicit trial profile: source archive remains immutable and SHA256-pinned.
if [[ "${FIRE4NIX_WPE_R36H_PLATFORM_PATCH:-0}" == 1 ]]; then
  python3 "$base/fire4nix/scripts/patch-wpe2541-r36h-platform.py" \
    --source-root "$work/source" --report "$work/report/r36h-platform-patch.json" \
    | tee -a "$work/report/status.txt"
fi
# Optional cross-compiler cache for future authentic ROCKNIX builds. This
# is a HOST executable only; never replace the target GCC or target libc.
# Disabled unless a CI workflow intentionally opts in. Compiler content,
# arguments and preprocessed input remain part of ccache's content key.
ccache_flags=()
if [[ "${FIRE4NIX_WPE_CCACHE:-0}" == "1" ]]; then
  launcher=$(command -v ccache) || {
    echo 'ERROR: requested GCC15 cross-build ccache unavailable' >&2; exit 29;
  }
  case "$launcher" in /usr/bin/ccache|/bin/ccache) ;; *)
    echo "ERROR: unapproved ccache path $launcher" >&2; exit 29 ;;
  esac
  [[ -n "${CCACHE_DIR:-}" && -d "$CCACHE_DIR" && ! -L "$CCACHE_DIR" ]] || {
    echo 'ERROR: explicit non-symlink CCACHE_DIR required when caching' >&2
    exit 29
  }
  ccache_flags=("-DCMAKE_C_COMPILER_LAUNCHER:STRING=$launcher"
                "-DCMAKE_CXX_COMPILER_LAUNCHER:STRING=$launcher")
  echo 'WPE_CCACHE_PROFILE=ROCKNIX_TARGET_GCC_OPT_IN' >> "$work/report/status.txt"
else
  [[ "${FIRE4NIX_WPE_CCACHE:-0}" == "0" ]] || {
    echo 'ERROR: invalid FIRE4NIX_WPE_CCACHE value' >&2; exit 29;
  }
  echo 'WPE_CCACHE_PROFILE=DISABLED' >> "$work/report/status.txt"
fi
# This is explicitly a CONFIGURE ONLY (never cmake --build / cmake --install).
set +e
# Wayland protocol XML is architecture-independent input for the HOST scanner,
# but must come from the pinned ROCKNIX 1.44 SDK rather than Ubuntu packages.
# The SDK was audited in stage 1; never silently fall back to /usr/share.
host_protocols="$stage/usr/share/wayland-protocols"
protocol_pc="$stage/usr/share/pkgconfig/wayland-protocols.pc"
test -s "$protocol_pc" || {
 echo 'ERROR: missing pinned ROCKNIX wayland-protocols.pc' >&2; exit 26;
}
test "$(pkg-config --modversion wayland-protocols)" = '1.44' || {
 echo 'ERROR: expected ROCKNIX Wayland Protocols 1.44, not host package' >&2; exit 26;
}
grep -Fq 'Version: 1.44' "$protocol_pc" || {
 echo 'ERROR: protocol metadata does not match ROCKNIX 1.44' >&2; exit 26;
}
echo 'WPE_WAYLAND_PROTOCOLS=ROCKNIX_1_44_DATA_ONLY' >> "$work/report/status.txt"
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
 "${ccache_flags[@]}" \
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
# C/C++ must both honor the GCC15 baseline ARMv8.0 inline atomics fix.
# Do not run a several-hour full build if CMake stripped either flag.
for language in C CXX; do
  grep -E "^CMAKE_${language}_FLAGS:STRING=.*-mno-outline-atomics([[:space:]]|$)" "$cache" >/dev/null || {
    echo "ERROR: CMake lost -mno-outline-atomics for $language" >&2
    exit 31
  }
done
echo 'WPE_ROCKNIX_GCC15_ATOMICS=NO_OUTLINE_VERIFIED_CMAKE_CACHE' >> "$work/report/status.txt"
if [[ "${FIRE4NIX_WPE_CCACHE:-0}" == "1" ]]; then
  grep -Fxq "CMAKE_C_COMPILER_LAUNCHER:STRING=$launcher" "$cache" || {
    echo 'ERROR: missing CMake C ccache launcher' >&2; exit 29;
  }
  grep -Fxq "CMAKE_CXX_COMPILER_LAUNCHER:STRING=$launcher" "$cache" || {
    echo 'ERROR: missing CMake C++ ccache launcher' >&2; exit 29;
  }
  echo 'WPE_CCACHE_CMAKE_CACHE=PASS_C_AND_CXX_TARGET_COMPILATION' >> "$work/report/status.txt"
fi
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
    sh "$base/fire4nix/scripts/verify-unified-wpe-media-cache.sh" --check \
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
echo 'WPE_CONFIGURE_PROBE=UNIFIED_ROCKNIX_STAGE1_WAYLAND_NO_GSTREAMER' >> "$work/report/status.txt"
cat "$work/report/status.txt"
