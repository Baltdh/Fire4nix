#!/bin/sh
# ROCKNIX Fire4Nix startup diagnostics. Run with: sh Fire4Nix-Start-Debug.sh
LOG=/storage/fire4nix-start-debug.log
[ -w /storage ] || LOG=/tmp/fire4nix-start-debug.log
exec >> "$LOG" 2>&1
echo "=== Fire4Nix debug $(date) ==="
echo "arch=$(uname -m) uid=$(id -u) pwd=$PWD"
echo "Wayland=${WAYLAND_DISPLAY:-unset} XDG=${XDG_RUNTIME_DIR:-unset}"
if [ -z "${WAYLAND_DISPLAY:-}" ]; then
  for s in /var/run/0-runtime-dir/wayland-* /run/user/0/wayland-* /run/user/*/wayland-*; do
    [ -S "$s" ] || continue
    XDG_RUNTIME_DIR=$(dirname "$s")
    WAYLAND_DISPLAY=$(basename "$s")
    export XDG_RUNTIME_DIR WAYLAND_DISPLAY
    break
  done
fi
echo "Resolved Wayland=${WAYLAND_DISPLAY:-unset} XDG=${XDG_RUNTIME_DIR:-unset}"
BASE=$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)
for candidate in "$BASE" "$BASE/navegador-definitivo" "$BASE/Fire4Nix" "$BASE/../navegador-definitivo" /storage/roms/ports/Fire4Nix; do
  [ -f "$candidate/Fire4Nix.sh" ] || continue
  echo "App=$candidate"
  cd "$candidate" || exit 1
  bash ./Fire4Nix.sh "$@"
  rc=$?
  echo "Fire4Nix exited: $rc"
  exit "$rc"
done
echo "ERROR: Fire4Nix.sh not found"
exit 3
