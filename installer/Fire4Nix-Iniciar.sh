#!/bin/sh
# Fire4Nix R36H 0.99: preserve diagnosis from the very first failing preflight.
set -u
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 2
BIN="$ROOT/bin/fire4nix-native-aarch64"
LOG_DIR=${FIRE4NIX_LOG_DIR:-$ROOT/logs}
if ! mkdir -p "$LOG_DIR" 2>/dev/null || [ ! -w "$LOG_DIR" ]; then
    LOG_DIR=${TMPDIR:-/tmp}
fi
# mktemp avoids collisions between simultaneous sessions without relying on
# process-ID expansion or synchronized handheld clocks.
LOG=$(mktemp "$LOG_DIR/Fire4Nix-$(date +%Y%m%d-%H%M%S)-XXXXXX.log") || {
    echo "Fire4Nix: unable to allocate unique diagnostic log" >&2
    exit 73
}
GAMEPAD_PID=""
stop_gamepad() {
    [ -n "$GAMEPAD_PID" ] || return 0
    # We only stop our own child, never a system-wide hotkey service.
    kill "$GAMEPAD_PID" 2>/dev/null || true
    wait "$GAMEPAD_PID" 2>/dev/null || true
    GAMEPAD_PID=""
}
start_gamepad() {
    [ "$MODE" = --open ] || return 0
    if [ "${FIRE4NIX_GAMEPAD:-auto}" = 0 ]; then
        echo "gamepad=disabled_by_user" >> "$LOG"
        return 0
    fi
    cfg="$ROOT/config/fire4nix.gptk"
    if [ ! -s "$cfg" ]; then
        echo "gamepad=no_controller_profile" >> "$LOG"
        return 0
    fi
    keybin=${FIRE4NIX_GPTOKEYB:-}
    if [ -z "$keybin" ]; then
        keybin=$(command -v gptokeyb 2>/dev/null || true)
    fi
    if [ -z "$keybin" ]; then
        for candidate in /usr/bin/gptokeyb /usr/local/bin/gptokeyb /usr/sbin/gptokeyb; do
            if [ -x "$candidate" ]; then keybin="$candidate"; break; fi
        done
    fi
    if [ -z "$keybin" ] || [ ! -x "$keybin" ]; then
        echo "gamepad=gptokeyb_missing_or_not_executable" >> "$LOG"
        return 0
    fi
    if command -v pgrep >/dev/null 2>&1 && pgrep -x gptokeyb >/dev/null 2>&1; then
        echo "gamepad=skipped_existing_gptokeyb_to_avoid_duplicate_events" >> "$LOG"
        return 0
    fi
    # Do not use gptokeyb -k/-1: those options can kill an unrelated process.
    "$keybin" -c "$cfg" >> "$LOG" 2>&1 &
    GAMEPAD_PID=$!
    # A successful fork is not proof that gptokeyb can access SDL/uinput.
    # Give it a short scheduling opportunity, then capture immediate failures.
    sleep 0.15
    if ! kill -0 "$GAMEPAD_PID" 2>/dev/null; then
        helper_exit=0
        wait "$GAMEPAD_PID" 2>/dev/null || helper_exit=$?
        printf 'gamepad=helper_exited_early exit_code=%s\n' "$helper_exit" >> "$LOG"
        GAMEPAD_PID=""
        return 0
    fi
    printf 'gamepad=running pid=%s config=%s\n' "$GAMEPAD_PID" "$cfg" >> "$LOG"
}

if ! : > "$LOG" 2>/dev/null; then
    echo "Fire4Nix: cannot create diagnostic log under $LOG_DIR" >&2
    exit 73
fi
finish() {
    code=$?
    trap - 0
    stop_gamepad
    printf 'fire4nix_exit_code=%s\n' "$code" >> "$LOG"
    if [ -d /storage ] && [ -w /storage ]; then
        cp "$LOG" /storage/Fire4Nix-ultimo-resultado.txt 2>/dev/null || true
    fi
    tail -n 40 "$LOG" 2>/dev/null || true
    exit "$code"
}
trap finish 0
trap 'exit 130' INT
trap 'exit 143' TERM
fail() {
    code=$1
    shift
    printf 'Fire4Nix: %s\n' "$*" >&2
    printf 'error=%s\n' "$*" >> "$LOG"
    exit "$code"
}
# At most 12 log files; never delete the stable last-result copy in /storage.
ls -1t "$LOG_DIR"/Fire4Nix-*.log 2>/dev/null | sed -n '13,$p' |
while IFS= read -r old; do
    [ -f "$old" ] && rm -f "$old"
done
printf 'version=0.99\nroot=%s\n' "$ROOT" >> "$LOG"
MODE=--open
case "${1:-}" in
  --open|--smoke|--headless|--check-library|--check-platform|--selftest)
    MODE=$1
    shift ;;
  --*) fail 2 "Unsupported Fire4Nix option: $1" ;;
esac
printf 'mode=%s\n' "$MODE" >> "$LOG"
[ -f "$BIN" ] || fail 127 "Missing Fire4Nix ARM64 executable"
[ -x "$BIN" ] || chmod u+x "$BIN" 2>/dev/null || true
[ -x "$BIN" ] || fail 126 "ELF cannot execute (permissions/noexec)"
if [ "$MODE" = --selftest ]; then
    "$BIN" --selftest >> "$LOG" 2>&1
    exit $?
fi
LIB="$ROOT/runtime/lib/libWPEWebKit-2.0.so.1"
CHILD="$ROOT/runtime/libexec/wpe-webkit-2.0"
[ -s "$LIB" ] || fail 127 "Missing local WPE WebKit runtime"
for child in WPEWebProcess WPENetworkProcess WPEGPUProcess; do
    [ -s "$CHILD/$child" ] || fail 127 "Missing WebKit subprocess: $child"
done
export LD_LIBRARY_PATH="$ROOT/runtime/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export WEBKIT_EXEC_PATH="$CHILD"
export WPE_PLATFORM=wayland
unset WPE_DISPLAY
if [ "$MODE" = --headless ]; then
    export WPE_PLATFORM=headless
    MODE=--smoke
fi
if [ "$WPE_PLATFORM" = wayland ] &&
   [ "$MODE" != --check-platform ] && [ "$MODE" != --check-library ] &&
   [ ! -S "${XDG_RUNTIME_DIR:-/nowhere}/${WAYLAND_DISPLAY:-invalid}" ]; then
    for dir in /var/run/0-runtime-dir /run/user/0 "/run/user/$(id -u 2>/dev/null || echo 1000)"; do
        for socket in wayland-1 wayland-0; do
            if [ -S "$dir/$socket" ]; then
                export XDG_RUNTIME_DIR="$dir" WAYLAND_DISPLAY="$socket"
                break 2
            fi
        done
    done
fi
printf 'platform=%s\nsocket=%s/%s\n' "$WPE_PLATFORM" \
    "${XDG_RUNTIME_DIR:-none}" "${WAYLAND_DISPLAY:-none}" >> "$LOG"
if [ "$WPE_PLATFORM" = wayland ] &&
   [ "$MODE" != --check-platform ] && [ "$MODE" != --check-library ] &&
   [ ! -S "${XDG_RUNTIME_DIR:-/nowhere}/${WAYLAND_DISPLAY:-invalid}" ]; then
    fail 69 "Wayland socket unavailable: start Fire4Nix from ROCKNIX Ports under Sway"
fi
export FIRE4NIX_LOW_MEMORY=${FIRE4NIX_LOW_MEMORY:-1}
export MALI_WAYLAND_AFBC=${MALI_WAYLAND_AFBC:-0}
export FIRE4NIX_HOME_URL="${FIRE4NIX_HOME_URL:-file://$ROOT/www/inicio.html}"
URL=${1:-$FIRE4NIX_HOME_URL}
start_gamepad
case "$MODE" in
  --check-library|--check-platform) "$BIN" "$MODE" >> "$LOG" 2>&1; code=$? ;;
  --smoke) "$BIN" --smoke "$URL" >> "$LOG" 2>&1; code=$? ;;
  --open) "$BIN" "$URL" >> "$LOG" 2>&1; code=$? ;;
esac
exit "$code"
