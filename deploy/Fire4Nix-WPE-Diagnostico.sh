#!/bin/sh
# Run on the actual ROCKNIX device. Read-only checks; no installation.
set -u
find_app_for_diagnostic() {
 if [ -n "${FIRE4NIX_APP_DIR:-}" ]; then
   printf '%s\n' "$FIRE4NIX_APP_DIR"
   return 0
 fi
 script_dir="$(CDPATH='' cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P)" || script_dir=.
 for candidate in \
   "$script_dir" \
   "$script_dir/Fire4Nix" \
   "$script_dir/navegador-definitivo" \
   "$script_dir/../Fire4Nix" \
   "$script_dir/../navegador-definitivo" \
   /storage/roms/tools/Fire4Nix \
   /storage/roms/Tools/Fire4Nix \
   /storage/roms/ports/Fire4Nix; do
   if [ -f "$candidate/Fire4Nix.sh" ]; then
     (CDPATH='' cd -- "$candidate" && pwd -P)
     return 0
   fi
 done
 printf '%s\n' /storage/roms/ports/Fire4Nix
}
APP="$(find_app_for_diagnostic)"
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
if [ ! -f "$APP/Fire4Nix.sh" ]; then
 echo "WARNING: no Fire4Nix.sh found at application path; put diagnostic beside the app or set FIRE4NIX_APP_DIR"
fi
for f in "$APP/fire4nix-wpe-platform" "$APP/bin/wpe-platform-launcher" "$APP/bin/wpe-platform" "$APP/build/fire4nix-wpe-platform" "$APP/bin/fire4nix-wpe-platform" "$APP/bin/browser.arm64"; do
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
 if command -v ldd >/dev/null 2>&1 && [ -x "$f" ]; then
   dependencies="$(ldd "$f" 2>&1 || true)"
   case "$dependencies" in
     *'not found'*) echo "WARNING: unresolved shared libraries for $f"; printf '%s\n' "$dependencies" | grep 'not found' ;;
   esac
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
