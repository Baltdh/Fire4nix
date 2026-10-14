#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
source "$ROOT/navegador-definitivo/scripts/fire4nix_env.sh"
# Unit fixtures model socket existence; no compositor or privileged socket needed.
mkdir -p "$TMP/session"
touch "$TMP/session/wayland-1"
fire4nix_wayland_socket_exists() { [ "$1" = "$TMP/session/wayland-1" ]; }
export XDG_RUNTIME_DIR="$TMP/session" WAYLAND_DISPLAY=wayland-0
fire4nix_recover_wayland_session
[ "$WAYLAND_DISPLAY" = wayland-1 ]
[ "$(fire4nix_wpe_display_name)" = wpe-display-wayland ]
export WAYLAND_DISPLAY="$TMP/session/wayland-1" XDG_RUNTIME_DIR="$TMP/other"
fire4nix_recover_wayland_session
[ "$WAYLAND_DISPLAY" = "$TMP/session/wayland-1" ]
[ "$(fire4nix_wpe_display_name)" = wpe-display-wayland ]
export WAYLAND_DISPLAY=missing XDG_RUNTIME_DIR="$TMP/absent"
fire4nix_recover_wayland_session
[ "$WAYLAND_DISPLAY" = missing ]
echo 'PASS: session recovery and absolute Wayland socket selection'
# With no Cog installed, preserve the actual native preflight failure.
fire4nix_apply_engine_selection() { :; }
fire4nix_wpe_platform_binary() { printf '%s\n' /bin/false; }
fire4nix_wpe_runtime_env() { :; }
fire4nix_activate_bundled_wpe_runtime() { return 1; }
command() {
    if [ "${1:-}" = -v ] && [ "${2:-}" = cog ]; then return 1; fi
    builtin command "$@"
}
if fire4nix_launch_wpe_platform about:blank > "$TMP/failure.log" 2>&1; then
    echo 'FAIL: failed preflight reported success' >&2; exit 1
else
    [ "$?" = 126 ]
fi
grep -q 'WPE failed (exit 126)' "$TMP/failure.log"
echo 'PASS: missing Cog does not hide native runtime failure'
