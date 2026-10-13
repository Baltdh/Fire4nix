#!/bin/sh
# Fire4Nix ROCKNIX diagnostics - safe launcher probe
LOG=/storage/fire4nix-diagnostic.log
exec >"$LOG" 2>&1
echo "Fire4Nix diagnostic $(date)"
echo "PATH=$PATH"
uname -a
id
echo "DISPLAY=${DISPLAY:-unset} WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-unset} XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-unset}"
echo "=== available engines ==="
for cmd in wpe-webkit-launcher cog firefox chromium weston xwayland Xwayland; do command -v "$cmd" || true; done
echo "=== libraries ==="
for p in /usr/lib/libWPEBackend-fdo* /usr/lib/libwebkit* /usr/lib/libWPEWebKit* /usr/lib64/libWPE*; do [ ! -e "$p" ] || ls -l "$p"; done
echo "=== storage scripts ==="
for p in /storage/roms/scripts /storage/roms/tools /storage/.config; do [ ! -d "$p" ] || ls -ld "$p"; done
echo "=== done ==="
sync
