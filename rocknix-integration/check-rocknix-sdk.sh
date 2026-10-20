#!/bin/sh
# Fail-closed, read-only sysroot check for Fire4Nix WPE cross-builds.
# This does not execute target binaries, download sources or touch ROCKNIX.
set -eu
mode=${1:---check}
case "$mode" in --check|--help) ;; *) echo 'Usage: check-rocknix-sdk.sh [--check|--help]' >&2; exit 2;; esac
if [ "$mode" = --help ]; then
  echo 'Set FIRE4NIX_ROCKNIX_TOOLCHAIN (CMake toolchain file) and'
  echo 'FIRE4NIX_ROCKNIX_SYSROOT (absolute SDK target root directory).'
  echo 'Optionally FIRE4NIX_ROCKNIX_RELEASE=20260801|20261001.'
  echo 'Checks the sysroot libc ELF machine and maximum exported GLIBC version.'
  exit 0
fi
release=${FIRE4NIX_ROCKNIX_RELEASE:-20260801}
case "$release" in
  20260801) expected=2.41 ;;
  20261001) expected=2.44 ;;
  *) echo "ERROR: unsupported ROCKNIX release: $release" >&2; exit 4 ;;
esac
toolchain=${FIRE4NIX_ROCKNIX_TOOLCHAIN:-}
sysroot=${FIRE4NIX_ROCKNIX_SYSROOT:-}
[ -n "$toolchain" ] && [ -f "$toolchain" ] || {
  echo 'ERROR: FIRE4NIX_ROCKNIX_TOOLCHAIN must point to a CMake toolchain file' >&2
  exit 4
}
case "$sysroot" in
  /*) ;;
  *) echo 'ERROR: FIRE4NIX_ROCKNIX_SYSROOT must be an absolute directory path' >&2; exit 4 ;;
esac
[ -d "$sysroot" ] || { echo 'ERROR: SDK sysroot directory missing' >&2; exit 4; }
root=$(CDPATH= cd -- "$sysroot" && pwd -P)
[ "$root" != / ] || { echo 'ERROR: refusing host root directory as SDK sysroot' >&2; exit 4; }
command -v readelf >/dev/null 2>&1 || { echo 'ERROR: readelf missing on build host' >&2; exit 4; }
command -v readlink >/dev/null 2>&1 || { echo 'ERROR: readlink missing on build host' >&2; exit 4; }
libc=''
for candidate in \
  "$root/lib/libc.so.6" "$root/lib64/libc.so.6" \
  "$root/usr/lib/libc.so.6" "$root/usr/lib64/libc.so.6" \
  "$root/lib/aarch64-linux-gnu/libc.so.6" \
  "$root/usr/lib/aarch64-linux-gnu/libc.so.6"; do
  if [ -e "$candidate" ] || [ -L "$candidate" ]; then libc="$candidate"; break; fi
done
[ -n "$libc" ] || { echo 'ERROR: target libc.so.6 missing in recognized SDK sysroot locations' >&2; exit 4; }
real_libc=$(readlink -f "$libc") || { echo 'ERROR: unresolved sysroot libc symlink' >&2; exit 4; }
case "$real_libc" in
  "$root"/*) ;;
  *) echo 'ERROR: SDK libc resolves outside the sysroot (possible host contamination)' >&2; exit 4 ;;
esac
[ -f "$real_libc" ] || { echo 'ERROR: SDK libc target must be a regular file' >&2; exit 4; }
if ! readelf -h "$real_libc" 2>/dev/null | grep -Eq 'Machine:.*AArch64'; then
  echo 'ERROR: target libc is not an AArch64 ELF (wrong SDK or corrupted file)' >&2
  exit 4
fi
# Read maximum numeric GLIBC version definition, not a string or the host's libc.
# A glibc 2.44 libc also exports 2.41, so only checking presence is insufficient.
versions=$(readelf -V "$real_libc" 2>/dev/null | grep -oE 'Name: GLIBC_[0-9]+\.[0-9]+' | sed 's/Name: GLIBC_//' || true)
[ -n "$versions" ] || { echo 'ERROR: cannot determine target libc GLIBC version from ELF metadata' >&2; exit 4; }
highest=$(printf '%s\n' "$versions" | sort -Vu | tail -n 1)
[ "$highest" = "$expected" ] || {
  echo "ERROR: target libc GLIBC_$highest differs from ROCKNIX $release expectation GLIBC_$expected" >&2
  exit 4
}
echo "SDK_PREFLIGHT=PASS"
echo "release=$release"
echo "arch=AArch64"
echo "target_glibc=$highest"
echo "libc=$real_libc"
echo 'note=compiler_target_and_transitive_dependencies_still_require_CMake_and_runtime_audit'
