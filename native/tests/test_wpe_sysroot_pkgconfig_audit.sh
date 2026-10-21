#!/bin/sh
# CI fixture tests: fake .pc metadata only, no fake result presented as real SDK.
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
audit="$repo/rocknix-integration/audit-wpe-sysroot-pkgconfig.sh"
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
root="$t/mock-target-root"
mkdir -p "$root/usr/lib/pkgconfig"
FIRE4NIX_ROCKNIX_SYSROOT="$root" sh "$audit" --inspect > "$t/missing"
grep -Fxq 'SYSROOT_PC_AUDIT=BLOCKED_NO_TARGET_PKGCONFIG_DIRECTORIES' "$t/missing" && {
  echo 'ERROR: created target pkg-config directory not detected' >&2; exit 1;
}
grep -Fxq 'SYSROOT_PC_AUDIT=INCOMPLETE_TARGET_SDK' "$t/missing"
grep -Fxq 'TARGET_PC_MISSING_COUNT=22' "$t/missing"
set +e
FIRE4NIX_ROCKNIX_SYSROOT="$root" sh "$audit" --pc-ready > "$t/reject"
rc=$?
set -e
test "$rc" -eq 6
# Metadata fixtures in a fake root; none of these files is a compiled library.
for pc in glib-2.0 gio-2.0 harfbuzz harfbuzz-icu icu-uc icu-i18n \
  libjpeg epoxy libgcrypt libsoup-3.0 libtasn1 xkbcommon libxml-2.0 \
  libpng sqlite3 libwebp libwebpdemux zlib freetype2 libxslt \
  wayland-client wayland-protocols; do
  cat > "$root/usr/lib/pkgconfig/$pc.pc" <<PC
prefix=/usr
libdir=\${prefix}/lib
Name: $pc
Description: mock file for CI dependency-metadata audit ONLY
Version: 99.99
Libs: -L\${libdir} -lmock
Cflags: -I\${prefix}/include
PC
done
FIRE4NIX_ROCKNIX_SYSROOT="$root" sh "$audit" --pc-ready > "$t/all"
grep -Fxq 'SYSROOT_PC_AUDIT=PASS_TARGET_PKGCONFIG_METADATA_ONLY' "$t/all"
grep -Fxq 'TARGET_PC_MISSING_COUNT=0' "$t/all"
# Fail the minimum Soup3 version constraint.
sed -i 's/Version: 99.99/Version: 1.0/' "$root/usr/lib/pkgconfig/libsoup-3.0.pc"
set +e
FIRE4NIX_ROCKNIX_SYSROOT="$root" sh "$audit" --pc-ready > "$t/too-old"
rc=$?
set -e
test "$rc" -eq 6
grep -Fq 'TARGET_PC_MISSING_OR_OLD=libsoup-3.0 min=3.0.0' "$t/too-old"
# Never allow a host pkg-config directory to fill missing target dependencies.
rm -f "$root/usr/lib/pkgconfig/libtasn1.pc"
set +e
PKG_CONFIG_PATH="/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/share/pkgconfig" \
  FIRE4NIX_ROCKNIX_SYSROOT="$root" sh "$audit" --pc-ready > "$t/host-path"
rc=$?
set -e
test "$rc" -eq 6
grep -Fq 'TARGET_PC_MISSING_OR_OLD=libtasn1' "$t/host-path"
# A symlink in the sysroot path MUST NOT let the audit read a host .pc dir,
# even when PKG_CONFIG_PATH has been cleared.
mkdir -p "$t/external-pkgconfig" "$root/usr/lib64"
cat > "$t/external-pkgconfig/libtasn1.pc" <<'PC'
Name: libtasn1
Description: external metadata that must not be trusted
Version: 99.99
PC
ln -s "$t/external-pkgconfig" "$root/usr/lib64/pkgconfig"
set +e
FIRE4NIX_ROCKNIX_SYSROOT="$root" sh "$audit" --inspect > "$t/escaped"
rc=$?
set -e
test "$rc" -eq 6
grep -Fxq 'SYSROOT_PC_AUDIT=BLOCKED_HOST_PKGCONFIG_SYMLINK' "$t/escaped"
grep -Fxq 'TARGET_PC_DIRECTORY_OUTSIDE_SYSROOT=usr/lib64/pkgconfig' "$t/escaped"
echo 'PASS: 22 target .pc gates, minimum version, missing recipes, host pkg-config paths/symlinks rejected'
echo 'WARNING: tests use fake .pc files; no ROCKNIX SDK or native WebKit compiled'
