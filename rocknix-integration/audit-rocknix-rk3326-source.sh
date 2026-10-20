#!/bin/sh
# Fire4Nix: inspect pinned ROCKNIX 20260801 sources BEFORE any large build.
# Safe: no source writes, package build, SDK download, cross-load or firmware edits.
set -eu
mode=${1:---check}
case "$mode" in
  --check|--ready) ;;
  --help) echo 'FIRE4NIX_ROCKNIX_SOURCE=/path/to/ROCKNIX-20260801 sh audit-rocknix-rk3326-source.sh [--check|--ready]'; exit 0 ;;
  *) echo 'ERROR: --check or --ready expected' >&2; exit 2 ;;
esac
root=${FIRE4NIX_ROCKNIX_SOURCE:-}
[ -n "$root" ] && [ -d "$root" ] || { echo 'ERROR: set FIRE4NIX_ROCKNIX_SOURCE to a ROCKNIX source checkout' >&2; exit 4; }
[ -r "$root/Makefile" ] && [ -r "$root/packages/devel/glibc/package.mk" ] || {
  echo 'ERROR: ROCKNIX Makefile/glibc recipe absent'; exit 4
}
if ! grep -Eq '^PKG_VERSION="2[.]41"[[:space:]]*$' "$root/packages/devel/glibc/package.mk"; then
  echo 'ERROR: ROCKNIX source does not match target GLIBC 2.41 (20260801)'; exit 4
fi
if ! grep -Fq 'PROJECT=ROCKNIX DEVICE=RK3326 ARCH=aarch64 ./scripts/build_distro' "$root/Makefile"; then
  echo 'ERROR: missing ROCKNIX RK3326 aarch64 build target'; exit 4
fi
if [ -d "$root/.git" ] || [ -f "$root/.git" ]; then
  if command -v git >/dev/null 2>&1; then
    desc=$(git -C "$root" describe --tags --exact-match 2>/dev/null || true)
    [ "$desc" = 20260801 ] || {
      echo "ERROR: ROCKNIX repository must be checked out at tag 20260801; actual=${desc:-not-an-exact-tag}" >&2
      exit 4
    }
  fi
fi
echo 'ROCKNIX_SOURCE_AUDIT=1'
echo 'target=RK3326-aarch64'
echo 'source_release=20260801'
echo 'target_glibc_recipe=2.41'
echo 'source_mutated=no'
# Requirements from WebKit wpewebkit-2.54.1 Source/cmake/OptionsWPE.cmake.
# A package may be in generic packages/ OR overridden in projects/ROCKNIX/packages/.
# libsoup3 also needs TLS/network support (glib-networking, libpsl,
# nghttp2, gnutls) to implement HTTPS correctly; inspect those recipes too.
# Existence of a recipe DOES NOT confirm version/ABI or built SDK availability.
missing=0
found=0
for pkg in glib harfbuzz icu libjpeg-turbo libepoxy libgcrypt libsoup3 libtasn1 \
           libxkbcommon libxml2 libpng sqlite libwebp zlib freetype libxslt \
           wayland wayland-protocols \
           glib-networking libpsl nghttp2 gnutls; do
  path=$(find "$root/packages" "$root/projects/ROCKNIX/packages" \
         -type f -path "*/$pkg/package.mk" -print -quit 2>/dev/null || true)
  if [ -z "$path" ] && [ "$pkg" = libsoup3 ]; then
    # Some distributions name the Soup3 package 'libsoup'.
    candidate=$(find "$root/packages" "$root/projects/ROCKNIX/packages" \
       -type f -path '*/libsoup/package.mk' -print -quit 2>/dev/null || true)
    if [ -n "$candidate" ]; then
      echo "RECIPE_NEEDS_SOUP3_VERSION_CHECK=$candidate"
      path=$candidate
    fi
  fi
  if [ -z "$path" ]; then
    echo "MISSING_REQUIRED_RECIPE=$pkg"
    missing=$((missing + 1))
  else
    echo "RECIPE_FOUND=$pkg"
    found=$((found + 1))
  fi
done
echo "recipes_located=$found"
echo "missing_required_recipes=$missing"
if [ "$missing" -ne 0 ]; then
  echo 'NEXT_ACTION=PORT_MISSING_DEPENDENCY_RECIPES_BEFORE_WEBKIT_BUILD'
  echo 'status=SOURCE_MATCHED_BUT_DEPENDENCIES_INCOMPLETE'
  if [ "$mode" = --ready ]; then exit 6; fi
else
  echo 'NEXT_ACTION=VERIFY_DEPENDENCY_VERSIONS_THEN_BOOTSTRAP_TOOLCHAIN'
  echo 'status=SOURCE_MATCHED_RECIPES_FOUND_VERSIONS_UNCHECKED'
fi
echo 'browser_compiled=no'
echo 'sdk_compiled=no'
