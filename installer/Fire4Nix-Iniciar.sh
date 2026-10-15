#!/bin/sh
# Use the WPE installed alongside the launcher, NOT a global WebKit.
set -u
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 2
BIN="$ROOT/bin/fire4nix-native-aarch64"
# A URL can be supplied directly, without a preceding --open.
MODE=--open
case "${1:-}" in
  --open|--smoke|--headless|--check-library|--check-platform|--selftest)
    MODE=$1
    shift ;;
  --*) echo "Unsupported Fire4Nix option: $1" >&2; exit 2 ;;
esac
[ -f "$BIN" ] || { echo "Missing Fire4Nix ARM64 executable" >&2; exit 127; }
[ -x "$BIN" ] || chmod u+x "$BIN" 2>/dev/null || true
[ -x "$BIN" ] || { echo "ELF cannot execute (permissions/noexec)"; exit 126; }
if [ "$MODE" = --selftest ]; then exec "$BIN" --selftest; fi
LIB="$ROOT/runtime/lib/libWPEWebKit-2.0.so.1"
CHILD="$ROOT/runtime/libexec/wpe-webkit-2.0"
[ -s "$LIB" ] || { echo "Missing local WebKit runtime (174MB)" >&2; exit 127; }
for child in WPEWebProcess WPENetworkProcess WPEGPUProcess; do
    [ -s "$CHILD/$child" ] || { echo "Missing child $child" >&2; exit 127; }
done
export LD_LIBRARY_PATH="$ROOT/runtime/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export WEBKIT_EXEC_PATH="$CHILD"
# WPEPlatform >=2.54 uses WPE_PLATFORM; legacy WPE_DISPLAY alias caused aborts.
export WPE_PLATFORM=wayland
unset WPE_DISPLAY
if [ "$MODE" = --headless ]; then export WPE_PLATFORM=headless; MODE=--smoke; fi
if [ "$WPE_PLATFORM" = wayland ] && [ "$MODE" != --check-platform ] && [ "$MODE" != --check-library ] && [ ! -S "${XDG_RUNTIME_DIR:-/nowhere}/${WAYLAND_DISPLAY:-invalid}" ]; then
    for dir in /var/run/0-runtime-dir /run/user/0 "/run/user/$(id -u 2>/dev/null || echo 1000)"; do
        for socket in wayland-1 wayland-0; do
            if [ -S "$dir/$socket" ]; then
                export XDG_RUNTIME_DIR="$dir" WAYLAND_DISPLAY="$socket"
                break 2
            fi
        done
    done
fi
# Reject graphical startup when no running Sway socket can be found.
if [ "$WPE_PLATFORM" = wayland ] && [ "$MODE" != --check-platform ] && [ "$MODE" != --check-library ] && [ ! -S "${XDG_RUNTIME_DIR:-/nowhere}/${WAYLAND_DISPLAY:-invalid}" ]; then
    echo 'Fire4Nix: Wayland socket unavailable; start from ROCKNIX Ports under Sway.' >&2
    exit 69
fi
export FIRE4NIX_LOW_MEMORY=${FIRE4NIX_LOW_MEMORY:-1}
export MALI_WAYLAND_AFBC=${MALI_WAYLAND_AFBC:-0}
LOG_DIR=${FIRE4NIX_LOG_DIR:-$ROOT/logs}
mkdir -p "$LOG_DIR" 2>/dev/null || LOG_DIR=${TMPDIR:-/tmp}
LOG="$LOG_DIR/Fire4Nix-$(date +%Y%m%d-%H%M%S)-$$.log"
URL=${1:-file://$ROOT/www/inicio.html}
{ echo "mode=$MODE"; echo "platform=$WPE_PLATFORM"; echo "socket=${XDG_RUNTIME_DIR:-none}/${WAYLAND_DISPLAY:-none}"; } > "$LOG"
case "$MODE" in
  --check-library|--check-platform) "$BIN" "$MODE" >> "$LOG" 2>&1; code=$? ;;
  --smoke) "$BIN" --smoke "$URL" >> "$LOG" 2>&1; code=$? ;;
  --open) "$BIN" "$URL" >> "$LOG" 2>&1; code=$? ;;
esac
printf 'fire4nix_exit_code=%s\n' "$code" >> "$LOG"
tail -n 60 "$LOG"
if [ -d /storage ] && [ -w /storage ]; then cp "$LOG" /storage/Fire4Nix-ultimo-resultado.txt 2>/dev/null || true; fi
exit "$code"
