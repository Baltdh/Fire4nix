#!/bin/sh
set -eu
PC="${PKG_CONFIG:-pkg-config}"
command -v "$PC" >/dev/null 2>&1 || { echo "pkg-config: missing"; exit 2; }
echo "Fire4Nix WPE dependency probe"
echo "PKG_CONFIG=$PC"
found=0
for pkg in wpe-webkit-2.0 wpe-platform-wayland-2.0 wpe-platform-2.0 wpe-webkit wpewebkit libwpe-1.0 wpebackend-fdo-1.0; do
  if "$PC" --exists "$pkg" >/dev/null 2>&1; then
    echo "$pkg=$("$PC" --modversion "$pkg")"
    found=1
  else
    echo "$pkg=missing"
  fi
done
if [ -n "${WAYLAND_DISPLAY:-}" ]; then echo "WAYLAND_DISPLAY=$WAYLAND_DISPLAY"; else echo "WAYLAND_DISPLAY=unset"; fi
if [ -n "${WPE_DISPLAY:-}" ]; then echo "WPE_DISPLAY=$WPE_DISPLAY"; else echo "WPE_DISPLAY=unset"; fi
[ "$found" -eq 1 ] || exit 3
