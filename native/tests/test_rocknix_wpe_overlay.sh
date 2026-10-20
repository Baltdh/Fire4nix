#!/bin/sh
# Host-only fixtures: never builds ROCKNIX/WebKit or touches handheld storage.
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
audit="$repo/rocknix-integration/audit-rocknix-rk3326-source.sh"
verify="$repo/rocknix-integration/verify-rocknix-wpe-overlay.sh"
apply="$repo/rocknix-integration/apply-rocknix-wpe-overlay.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' 0
root="$T/rocknix"
mkdir -p "$root/packages/devel/glibc" "$root/projects/ROCKNIX/packages"
printf 'PKG_VERSION="2.41"\n' > "$root/packages/devel/glibc/package.mk"
printf 'RK3326:\n\tPROJECT=ROCKNIX DEVICE=RK3326 ARCH=aarch64 ./scripts/build_distro\n' > "$root/Makefile"
for name in glib harfbuzz icu libjpeg-turbo libepoxy libgcrypt \
            libxkbcommon libxml2 libpng sqlite libwebp zlib freetype libxslt \
            wayland wayland-protocols nghttp2 gnutls; do
  mkdir -p "$root/packages/mock/$name"
  printf 'PKG_NAME="%s"\n' "$name" > "$root/packages/mock/$name/package.mk"
done
FIRE4NIX_ROCKNIX_SOURCE="$root" sh "$audit" --check > "$T/before"
grep -Fqx 'missing_required_recipes=4' "$T/before"
sh "$verify" > "$T/meta"
grep -Fqx 'ROCKNIX_OVERLAY_STATUS=FOUR_PINNED_RECIPES_METADATA_VERIFIED_NOT_COMPILED' "$T/meta"
FIRE4NIX_ROCKNIX_SOURCE="$root" sh "$apply" --check > "$T/check"
grep -Fqx 'SOURCE_RECIPE_WRITES=no' "$T/check"
test ! -e "$root/packages/web/libsoup3/package.mk"
set +e
FIRE4NIX_ROCKNIX_SOURCE="$root" sh "$apply" --apply > "$T/no-consent" 2>&1
rc=$?
set -e
test "$rc" -eq 5
test ! -e "$root/packages/web/libsoup3/package.mk"
FIRE4NIX_ROCKNIX_SOURCE="$root" FIRE4NIX_OVERLAY_ALLOW_APPLY=1 \
  sh "$apply" --apply > "$T/staged"
grep -Fqx 'OVERLAY_APPLIED=FOUR_SOURCE_RECIPES_NOT_BUILT' "$T/staged"
grep -Fqx 'missing_required_recipes=0' "$T/staged"
test -f "$root/packages/web/libsoup3/package.mk"
test -f "$root/packages/network/glib-networking/package.mk"
set +e
FIRE4NIX_ROCKNIX_SOURCE="$root" FIRE4NIX_OVERLAY_ALLOW_APPLY=1 \
  sh "$apply" --apply > "$T/duplicate" 2>&1
rc=$?
set -e
test "$rc" -eq 5
grep -q 'would overwrite an existing ROCKNIX' "$T/duplicate"
FIRE4NIX_ROCKNIX_SOURCE="$root" sh "$audit" --ready > "$T/after"
grep -Fqx 'status=SOURCE_MATCHED_RECIPES_FOUND_VERSIONS_UNCHECKED' "$T/after"
# The overlay validator must also fail closed on broken TLS settings.
cp -a "$repo/rocknix-integration/rocknix-overlay" "$T/bad-overlay"
sed -i 's/-Dgnutls=enabled/-Dgnutls=disabled/' \
  "$T/bad-overlay/packages/network/glib-networking/package.mk"
set +e
FIRE4NIX_ROCKNIX_OVERLAY="$T/bad-overlay" sh "$verify" > "$T/unsafe-tls" 2>&1
rc=$?
set -e
test "$rc" -eq 5
grep -q 'GNUTLS GIO module cannot be disabled' "$T/unsafe-tls"
echo 'PASS: four pinned recipes, guarded Soup/TLS/PSL, no-overwrite overlay and 4-to-0 source dependencies'
