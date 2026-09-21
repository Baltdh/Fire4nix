#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

PKG_CONFIG_BIN="${PKG_CONFIG:-pkg-config}"
CXX_BIN="${CXX:-g++}"
OUT="${WPE_TARGET:-fire4nix-wpe-platform}"

fail() { printf 'Fire4Nix WPE build: ERROR: %s\n' "$*" >&2; exit 2; }

command -v "$PKG_CONFIG_BIN" >/dev/null 2>&1 || fail "pkg-config not found"
command -v "$CXX_BIN" >/dev/null 2>&1 || fail "C++ compiler not found"

WPE_PKG=""
for pkg in wpe-webkit-2.0 wpe-webkit wpewebkit; do
    if "$PKG_CONFIG_BIN" --exists "$pkg" >/dev/null 2>&1; then
        WPE_PKG="$pkg"
        break
    fi
done
[ -n "$WPE_PKG" ] || fail "WPE WebKit development package not found"

WPE_PLATFORM_PKG=""
for pkg in wpe-platform-wayland-2.0 wpe-platform-2.0; do
    if "$PKG_CONFIG_BIN" --exists "$pkg" >/dev/null 2>&1; then
        WPE_PLATFORM_PKG="$pkg"
        break
    fi
done

if [ "$WPE_PKG" = "wpe-webkit-2.0" ] && [ -z "$WPE_PLATFORM_PKG" ]; then
    fail "wpe-webkit-2.0 requires WPE Platform; install wpe-platform-wayland-2.0 (preferred) or wpe-platform-2.0"
fi

MIN_SECURE_WPE="${FIRE4NIX_MIN_SECURE_WPE:-2.52.6}"
if ! "$PKG_CONFIG_BIN" --atleast-version="$MIN_SECURE_WPE" "$WPE_PKG" >/dev/null 2>&1; then
    if [ "${FIRE4NIX_ALLOW_OLD_WPE:-0}" = "1" ]; then
        printf "Fire4Nix WPE build: WARNING: %s is older than security baseline %s\n" "$WPE_PKG" "$MIN_SECURE_WPE" >&2
    else
        fail "$WPE_PKG is older than security baseline $MIN_SECURE_WPE; set FIRE4NIX_ALLOW_OLD_WPE=1 only for offline compatibility testing"
    fi
fi

TRIPLE=$("$CXX_BIN" -dumpmachine 2>/dev/null || true)
case "$TRIPLE" in
    aarch64*|arm64*) ;;
    *) fail "compiler target '$TRIPLE' is not ARM64/aarch64; refusing to label a host binary as ROCKNIX ARM64" ;;
esac

printf 'Fire4Nix WPE package: %s %s\n' "$WPE_PKG" "$("$PKG_CONFIG_BIN" --modversion "$WPE_PKG")"
printf 'Fire4Nix WPE platform package: %s\n' "${WPE_PLATFORM_PKG:-legacy/not-found}"
printf 'Fire4Nix compiler target: %s\n' "$TRIPLE"

make PKG_CONFIG="$PKG_CONFIG_BIN" CXX="$CXX_BIN" WPE_PKG_NAME="$WPE_PKG" WPE_PLATFORM_PKG_NAME="$WPE_PLATFORM_PKG" WPE_TARGET="$OUT" wpe-platform-launcher

[ -f "$OUT" ] || fail "expected output '$OUT' was not created"
[ -x "$OUT" ] || chmod +x "$OUT"

if command -v file >/dev/null 2>&1; then
    DESC=$(file -b "$OUT")
    printf 'Fire4Nix output: %s\n' "$DESC"
    printf '%s' "$DESC" | grep -Eiq 'ELF 64-bit.*(ARM aarch64|ARM64|aarch64)' ||
        fail "output is not an ARM64 ELF executable"
else
    printf 'Fire4Nix WPE build: warning: file(1) unavailable; ELF architecture was not independently verified\n' >&2
fi

mkdir -p bin
cp -f "$OUT" bin/fire4nix-wpe-platform
chmod +x bin/fire4nix-wpe-platform
printf 'Fire4Nix WPE ARM64 launcher installed at %s/bin/fire4nix-wpe-platform\n' "$ROOT_DIR"
