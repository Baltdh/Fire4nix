#!/bin/sh
# Fire4Nix stage 1: read-only target SDK pkg-config readiness audit.
# Does not build, execute target ELF, install firmware or mutate sysroot.
set -eu
mode=${1:---inspect}
case "$mode" in --inspect|--pc-ready) ;; --help)
  echo 'FIRE4NIX_STAGE1_ROOT=/absolute/sysroot sh audit-wpe-sysroot-pkgconfig.sh --inspect|--pc-ready'; exit 0;;
  *) echo 'ERROR: use --inspect or --pc-ready' >&2; exit 2;;
esac
root=${FIRE4NIX_STAGE1_ROOT:-}
case "$root" in /*) ;; *) echo 'ERROR: absolute target sysroot required' >&2; exit 4;; esac
[ -d "$root" ] || { echo 'ERROR: sysroot directory missing' >&2; exit 4; }
root=$(CDPATH= cd "$root" && pwd -P)
case "$root" in /|/usr|/usr/*|/storage|/storage/*)
  echo 'ERROR: refusing host filesystem/ROCKNIX runtime as SDK' >&2; exit 4;;
esac
command -v pkg-config >/dev/null 2>&1 || { echo 'ERROR: pkg-config required' >&2; exit 4; }
# Explicitly lock target pkg-config search. A host libSoup .pc passing here would
# invalidate the result, even if target GCC is AArch64.
libdirs=
for p in usr/lib/pkgconfig usr/lib64/pkgconfig usr/share/pkgconfig \
  usr/lib/aarch64-linux-gnu/pkgconfig lib/pkgconfig lib64/pkgconfig \
  lib/aarch64-linux-gnu/pkgconfig; do
  if [ -d "$root/$p" ]; then
    # A pathname beginning with the SDK prefix can still be a symlink to
    # host /usr/lib. Canonicalize every search directory before pkg-config.
    realdir=$(CDPATH= cd "$root/$p" && pwd -P) || {
      echo "SYSROOT_PC_AUDIT=BLOCKED_UNRESOLVABLE_TARGET_PKGCONFIG_DIR"
      exit 6
    }
    case "$realdir" in
      "$root"/*) ;;
      *)
        echo "TARGET_PC_DIRECTORY_OUTSIDE_SYSROOT=$p"
        echo 'SYSROOT_PC_AUDIT=BLOCKED_HOST_PKGCONFIG_SYMLINK'
        exit 6 ;;
    esac
    if [ -z "$libdirs" ]; then libdirs="$realdir"; else libdirs="$libdirs:$realdir"; fi
  fi
done
[ -n "$libdirs" ] || {
  echo 'SYSROOT_PC_AUDIT=BLOCKED_NO_TARGET_PKGCONFIG_DIRECTORIES'
  [ "$mode" != --pc-ready ] || exit 6
  exit 0
}
export PKG_CONFIG_LIBDIR="$libdirs"
export PKG_CONFIG_SYSROOT_DIR="$root"
export PKG_CONFIG_PATH=''
# Avoid external settings silently overwriting intended target SDK.
unset PKG_CONFIG_TOP_BUILD_DIR PKG_CONFIG_SYSTEM_LIBRARY_PATH PKG_CONFIG_SYSTEM_INCLUDE_PATH || true
count=0
missing=0
# Versions from upstream wpewebkit-2.54.1/Source/cmake/OptionsWPE.cmake.
# This is an early gate; upstream CMake Find modules remain authoritative.
while IFS='|' read -r pc minimum; do
  [ -n "$pc" ] || continue
  count=$((count+1))
  if pkg-config --exists "$pc >= $minimum" 2>/dev/null; then
    origin=$(pkg-config --variable=pcfiledir "$pc" 2>/dev/null || true)
    case "$origin" in "$root"/*)
      echo "TARGET_PC_OK=$pc version=$(pkg-config --modversion "$pc")";;
    *)
      echo "TARGET_PC_HOST_CONTAMINATION=$pc origin=$origin"
      missing=$((missing+1));;
    esac
  else
    echo "TARGET_PC_MISSING_OR_OLD=$pc min=$minimum"
    missing=$((missing+1))
  fi
done <<'PACKAGES'
glib-2.0|2.70.0
gio-2.0|2.70.0
harfbuzz|2.7.4
harfbuzz-icu|2.7.4
icu-uc|70.1
icu-i18n|70.1
libjpeg|1.0
epoxy|1.5.4
libgcrypt|1.7.0
libsoup-3.0|3.0.0
libtasn1|1.0
xkbcommon|0.4.0
libxml-2.0|2.9.13
libpng|1.0
sqlite3|3.0
libwebp|1.0
libwebpdemux|1.0
zlib|1.0
freetype2|2.9.0
libxslt|1.1.13
wayland-client|1.20
wayland-protocols|1.24
PACKAGES
echo "TARGET_PC_TOTAL=$count"
echo "TARGET_PC_MISSING_COUNT=$missing"
if [ "$missing" -eq 0 ]; then
  echo 'SYSROOT_PC_AUDIT=PASS_TARGET_PKGCONFIG_METADATA_ONLY'
else
  echo 'SYSROOT_PC_AUDIT=INCOMPLETE_TARGET_SDK'
  echo 'NEXT_ACTION=COMPILE_OR_STAGE_MISSING_PACKAGES_WITH_ROCKNIX_TOOLCHAIN'
  if [ "$mode" = --pc-ready ]; then exit 6; fi
fi
echo 'VALIDATION_LIMIT=DOES_NOT_PROVE_ELF_ABI_COMPILER_OR_WPE_RENDERING'
