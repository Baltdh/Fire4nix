#!/bin/sh
# Run on the actual ROCKNIX device. Read-only checks; no installation.
set -u
APP="${FIRE4NIX_APP_DIR:-/storage/roms/ports/Fire4Nix}"
echo "=== Fire4Nix WPE preflight ==="
echo "architecture: $(uname -m)"
echo "app: $APP"
echo "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-unset}"
echo "WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-unset}"
for cmd in bash cog file readelf ldd pkg-config; do
 if command -v "$cmd" >/dev/null 2>&1; then
   echo "command $cmd: $(command -v "$cmd")"
 else
   echo "command $cmd: MISSING"
 fi
done
for f in "$APP/bin/wpe-platform-launcher" "$APP/bin/wpe-platform" "$APP/build/fire4nix-wpe-platform" "$APP/bin/fire4nix-wpe-platform" "$APP/bin/browser.arm64"; do
 [ -f "$f" ] || continue
 echo "--- $f"
 if command -v file >/dev/null 2>&1; then file "$f"; else
   IFS= read -r first < "$f" || true
   case "$first" in '#!'*) echo "script: $first";; *) echo "type: unknown (file command unavailable)";; esac
 fi
 if command -v readelf >/dev/null 2>&1; then
   readelf -h "$f" 2>/dev/null | grep -E 'Class:|Machine:' || true
   readelf -d "$f" 2>/dev/null | grep NEEDED || true
 fi
done
for name in libWPEBackend-fdo-1.0.so libwpe-1.0.so libWPEWebKit-2.0.so libwebkit2gtk-4.1.so; do
 if command -v ldconfig >/dev/null 2>&1; then
   ldconfig -p 2>/dev/null | grep -F "$name" || true
 fi
done
if [ -n "${WAYLAND_DISPLAY:-}" ] && [ -n "${XDG_RUNTIME_DIR:-}" ]; then
 if [ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]; then echo "Wayland socket: OK"; else echo "Wayland socket: MISSING"; fi
else
 echo "Wayland socket: environment unavailable"
fi
echo "=== end ==="
