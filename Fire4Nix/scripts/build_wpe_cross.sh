#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

fail() {
    printf 'Fire4Nix cross build: ERROR: %s\n' "$*" >&2
    exit 2
}

SYSROOT="${ROCKNIX_SYSROOT:-${FIRE4NIX_SYSROOT:-}}"
[ -n "$SYSROOT" ] || fail "set ROCKNIX_SYSROOT to an extracted aarch64 ROCKNIX sysroot"
[ -d "$SYSROOT" ] || fail "sysroot does not exist: $SYSROOT"

CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"
CXX_BIN="${CXX:-${CROSS_COMPILE}g++}"
PKG_CONFIG_BIN="${PKG_CONFIG:-pkg-config}"

command -v "$CXX_BIN" >/dev/null 2>&1 || fail "cross compiler not found: $CXX_BIN"
command -v "$PKG_CONFIG_BIN" >/dev/null 2>&1 || fail "pkg-config not found: $PKG_CONFIG_BIN"

TRIPLE=$("$CXX_BIN" -dumpmachine 2>/dev/null || true)
case "$TRIPLE" in
    aarch64*|arm64*) ;;
    *) fail "compiler target '$TRIPLE' is not ARM64/aarch64" ;;
esac

PKG_DIRS=""
for candidate in     "$SYSROOT/usr/lib/aarch64-linux-gnu/pkgconfig"     "$SYSROOT/usr/lib64/pkgconfig"     "$SYSROOT/usr/lib/pkgconfig"     "$SYSROOT/usr/share/pkgconfig"     "$SYSROOT/lib/aarch64-linux-gnu/pkgconfig"     "$SYSROOT/lib64/pkgconfig"     "$SYSROOT/lib/pkgconfig"
do
    [ -d "$candidate" ] || continue
    if [ -z "$PKG_DIRS" ]; then
        PKG_DIRS="$candidate"
    else
        PKG_DIRS="$PKG_DIRS:$candidate"
    fi
done

[ -n "$PKG_DIRS" ] || fail "no pkg-config directories found inside the ROCKNIX sysroot"

export FIRE4NIX_SYSROOT="$SYSROOT"
export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"
export PKG_CONFIG_LIBDIR="$PKG_DIRS"
unset PKG_CONFIG_PATH || true

printf 'Fire4Nix cross build sysroot: %s\n' "$SYSROOT"
printf 'Fire4Nix cross compiler: %s (%s)\n' "$CXX_BIN" "$TRIPLE"
printf 'Fire4Nix pkg-config libdir: %s\n' "$PKG_CONFIG_LIBDIR"

CXX="$CXX_BIN" PKG_CONFIG="$PKG_CONFIG_BIN" sh "$ROOT_DIR/scripts/build_wpe_arm64.sh"
