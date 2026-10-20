#!/bin/sh
# Fixtures only: no real SDK, ROCKNIX downloads or WPE binaries.
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
CHECK="$REPO/rocknix-integration/audit-rocknix-rk3326-source.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' 0
mkdir -p "$T/packages/devel/glibc" "$T/projects/ROCKNIX/packages"
printf 'PKG_VERSION="2.41"\n' > "$T/packages/devel/glibc/package.mk"
printf 'RK3326:\n\tPROJECT=ROCKNIX DEVICE=RK3326 ARCH=aarch64 ./scripts/build_distro\n' > "$T/Makefile"
for pkg in glib harfbuzz icu libjpeg-turbo libepoxy libgcrypt \
           libxkbcommon libxml2 libpng sqlite libwebp zlib freetype libxslt \
           wayland wayland-protocols nghttp2 gnutls; do
  mkdir -p "$T/packages/test/$pkg"
  printf 'PKG_NAME="%s"\n' "$pkg" > "$T/packages/test/$pkg/package.mk"
done
FIRE4NIX_ROCKNIX_SOURCE="$T" sh "$CHECK" --check > "$T/partial"
for pkg in libsoup3 libtasn1 glib-networking libpsl; do
  grep -Fqx "MISSING_REQUIRED_RECIPE=$pkg" "$T/partial"
done
grep -Fqx 'missing_required_recipes=4' "$T/partial"
grep -Fqx 'browser_compiled=no' "$T/partial"
set +e
FIRE4NIX_ROCKNIX_SOURCE="$T" sh "$CHECK" --ready > "$T/blocked"
rc=$?
set -e
test "$rc" -eq 6
grep -Fqx 'status=SOURCE_MATCHED_BUT_DEPENDENCIES_INCOMPLETE' "$T/blocked"
for pkg in libsoup3 libtasn1 glib-networking libpsl; do
  mkdir -p "$T/projects/ROCKNIX/packages/test/$pkg"
  printf 'PKG_NAME="%s"\n' "$pkg" > "$T/projects/ROCKNIX/packages/test/$pkg/package.mk"
done
FIRE4NIX_ROCKNIX_SOURCE="$T" sh "$CHECK" --ready > "$T/ready"
grep -Fqx 'missing_required_recipes=0' "$T/ready"
grep -Fqx 'status=SOURCE_MATCHED_RECIPES_FOUND_VERSIONS_UNCHECKED' "$T/ready"
printf 'PKG_VERSION="2.44"\n' > "$T/packages/devel/glibc/package.mk"
set +e
FIRE4NIX_ROCKNIX_SOURCE="$T" sh "$CHECK" --check > "$T/wrong" 2>&1
rc=$?
set -e
test "$rc" -eq 4
grep -q 'does not match target GLIBC 2.41' "$T/wrong"
echo 'PASS: RK3326 and GLIBC gate; 4 missing direct/transitive recipe dependencies; wrong-rootfs refusal'
