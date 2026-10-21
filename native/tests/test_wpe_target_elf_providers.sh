#!/bin/sh
# Fixture test: build real AArch64 (not WebKit!) and host x86_64 ELF stubs.
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
script="$repo/rocknix-integration/audit-wpe-target-elf-providers.sh"
for cmd in clang pkg-config readelf; do command -v "$cmd" >/dev/null 2>&1 || exit 4; done
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
root="$work/sysroot"
mkdir -p "$root/usr/lib/pkgconfig" "$root/usr/lib/gio/modules"
printf 'int f(void){return 1;}\n' > "$work/probe.c"
clang --target=aarch64-linux-gnu -fuse-ld=lld -nostdlib -shared -fPIC "$work/probe.c" \
  -o "$root/usr/lib/libfixture.so"
cp "$root/usr/lib/libfixture.so" "$root/usr/lib/gio/modules/libgiognutls.so"
for pc in glib-2.0 gio-2.0 libsoup-3.0 libtasn1 harfbuzz epoxy wayland-client; do
  cat > "$root/usr/lib/pkgconfig/$pc.pc" <<PC
prefix=/usr
libdir=${prefix}/lib
Name: $pc
Description: test-only AArch64 provider
Version: 99.0
Libs: -L${libdir} -lfixture
PC
done
FIRE4NIX_ROCKNIX_SYSROOT="$root" sh "$script" --strict > "$work/pass"
grep -Fqx 'TARGET_ELF_AUDIT=PASS_STATIC_AARCH64_PROVIDERS_TLS_MODULE' "$work/pass"
grep -Fqx 'TARGET_LINK_FAILURES=0' "$work/pass"
# Existing .pc metadata is not enough if the underlying ELF is wrong-arch.
cp "$root/usr/lib/libfixture.so" "$work/arm64.so"
cc -nostdlib -shared -fPIC "$work/probe.c" -o "$root/usr/lib/libfixture.so"
if FIRE4NIX_ROCKNIX_SYSROOT="$root" sh "$script" --strict > "$work/x86"; then
  echo 'ERROR: host ELF unexpectedly accepted' >&2; exit 1
fi
grep -Fq 'TARGET_LINK_BLOCKED=NOT_AARCH64:' "$work/x86"
cp "$work/arm64.so" "$root/usr/lib/libfixture.so"
# Guard first candidate and dangling link (no fallback to later libraries).
mv "$root/usr/lib/libfixture.so" "$work/saved"
ln -s /usr/lib/host-library.so "$root/usr/lib/libfixture.so"
if FIRE4NIX_ROCKNIX_SYSROOT="$root" sh "$script" --strict > "$work/symlink"; then
  echo 'ERROR: external/broken symlink unexpectedly accepted' >&2; exit 1
fi
grep -Eq 'TARGET_LINK_BLOCKED=(NOT_REGULAR_FILE|HOST_OR_OUTSIDE_SYSROOT):' "$work/symlink"
rm "$root/usr/lib/libfixture.so"
mv "$work/saved" "$root/usr/lib/libfixture.so"
rm "$root/usr/lib/gio/modules/libgiognutls.so"
if FIRE4NIX_ROCKNIX_SYSROOT="$root" sh "$script" --strict > "$work/tls"; then
  echo 'ERROR: HTTPS backend missing but accepted' >&2; exit 1
fi
grep -Fqx 'TARGET_LINK_BLOCKED=MISSING_GIO_GNUTLS_MODULE:HTTPS_NOT_READY' "$work/tls"
cp "$work/arm64.so" "$root/usr/lib/gio/modules/libgiognutls.so"
# Ensure a hostile external pkg-config path cannot satisfy a missing SDK pc.
rm "$root/usr/lib/pkgconfig/libsoup-3.0.pc"
if PKG_CONFIG_PATH=/usr/lib/x86_64-linux-gnu/pkgconfig \
  FIRE4NIX_ROCKNIX_SYSROOT="$root" sh "$script" --strict > "$work/hostpc"; then
  echo 'ERROR: host pc injection unexpectedly accepted' >&2; exit 1
fi
grep -Fqx 'TARGET_LINK_BLOCKED=MISSING_PC:libsoup-3.0' "$work/hostpc"
echo 'PASS: real ARM64 ELF providers, rejected x86_64, unsafe link, missing TLS, host pc isolation'
echo 'FIXTURE_ONLY=yes (not a completed ROCKNIX SDK or WebKit runtime)'
