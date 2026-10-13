#!/usr/bin/env bash
# ROCKNIX-inspired filesystem/session simulation, not a full OS emulator.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/storage/games-external/Download/Fire4Nix" "$TMP/storage/.config" "$TMP/wayland" "$TMP/data"
cp "$ROOT/deploy/Fire4Nix-ROCKNIX.sh" "$TMP/storage/games-external/Download/Fire4Nix/Start.sh"
cat > "$TMP/storage/games-external/Download/Fire4Nix/Fire4Nix.sh" <<'APP'
#!/usr/bin/env bash
echo "SIMULATED_FIRE4NIX_OK pwd=$PWD wayland=${WAYLAND_DISPLAY:-unset} xdg=${XDG_RUNTIME_DIR:-unset}"
APP
chmod +x "$TMP/storage/games-external/Download/Fire4Nix/Start.sh"
LOG="$TMP/test.log"
env WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR="$TMP/wayland" FIRE4NIX_DATA_ROOT="$TMP/data" FIRE4NIX_LAUNCH_LOG="$LOG" "$TMP/storage/games-external/Download/Fire4Nix/Start.sh"
grep -q 'SIMULATED_FIRE4NIX_OK' "$LOG"
grep -q 'Browser exit code: 0' "$LOG"
ln -s "$TMP/storage/games-external/Download/Fire4Nix/Start.sh" "$TMP/shortcut.sh"
env WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR="$TMP/wayland" FIRE4NIX_DATA_ROOT="$TMP/data" FIRE4NIX_LAUNCH_LOG="$LOG" "$TMP/shortcut.sh"
test "$(grep -c SIMULATED_FIRE4NIX_OK "$LOG")" -eq 2
echo 'PASS: external Download path, Wayland environment, symlink, startup log'
echo 'LIMITATION: WPE native loader, GPU and actual ROCKNIX runtime not emulated'
