#!/usr/bin/env bash
# Test WPE on the actual ROCKNIX handheld, using only local HTML.
# NEVER disable the WebKit sandbox, use sudo, or install/replace system libs.
# The results are private files that remain available after Tools closes.
set -u
umask 077

MODE="headless"
case "${1:---headless}" in
    --headless) MODE="headless" ;;
    --wayland) MODE="wayland" ;;
    *)
        printf 'Usage: %s [--headless|--wayland]\n' "$0" >&2
        exit 2
        ;;
esac

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)" || exit 2
APP="${FIRE4NIX_APP_DIR:-}"
if [ -z "$APP" ]; then
    for candidate in \
        "$SCRIPT_DIR/Fire4Nix" \
        "$SCRIPT_DIR/navegador-definitivo" \
        "$SCRIPT_DIR" \
        "$SCRIPT_DIR/../Fire4Nix" \
        /storage/roms/tools/Fire4Nix \
        /storage/roms/Tools/Fire4Nix \
        /storage/roms/ports/Fire4Nix; do
        if [ -f "$candidate/Fire4Nix.sh" ] &&
           [ -f "$candidate/scripts/fire4nix_env.sh" ]; then
            APP="$candidate"
            break
        fi
    done
fi

BASE="${FIRE4NIX_DEVICE_TEST_REPORT_DIR:-}"
if [ -z "$BASE" ]; then
    if [ -d /storage ] && [ -w /storage ]; then
        BASE="/storage/fire4nix-device-tests"
    else
        BASE="${TMPDIR:-/tmp}/fire4nix-device-tests"
    fi
fi
if ! mkdir -p -- "$BASE" 2>/dev/null; then
    BASE="${TMPDIR:-/tmp}/fire4nix-device-tests"
    mkdir -p -- "$BASE" || { echo 'ERROR: cannot create report directory' >&2; exit 2; }
fi
chmod 700 "$BASE" 2>/dev/null || true
if ! command -v timeout >/dev/null 2>&1 ||
   ! command -v mktemp >/dev/null 2>&1; then
    # A Tools-launched terminal may close immediately. Save this failure even
    # when mktemp is unavailable, so the user can inspect it afterward.
    error_report="$BASE/PREFLIGHT-ERROR.txt"
    {
        echo 'Fire4Nix WPE device preflight FAILED'
        echo 'Missing required timeout or mktemp command; browser NOT started'
        echo "timeout: $(command -v timeout 2>/dev/null || echo MISSING)"
        echo "mktemp: $(command -v mktemp 2>/dev/null || echo MISSING)"
    } > "$error_report"
    cat "$error_report" >&2
    echo "Error report saved: $error_report" >&2
    exit 2
fi
RUN="$(mktemp -d "$BASE/test-$MODE.XXXXXXXX")" || exit 2
REPORT="$RUN/RESULT.txt"
LAUNCH_LOG="$RUN/launcher.log"
STATE="$RUN/browser-runtime/browser.state"
mkdir -p "$RUN/browser-runtime"
printf 'Fire4Nix ROCKNIX hardware WPE smoke test\n' > "$REPORT"
printf 'Mode: %s\n' "$MODE" >> "$REPORT"
printf 'Time: %s\n' "$(date 2>/dev/null || echo unknown)" >> "$REPORT"
printf 'App: %s\n' "${APP:-NOT FOUND}" >> "$REPORT"
printf 'Architecture: %s\n' "$(uname -m 2>/dev/null || echo unknown)" >> "$REPORT"
printf 'Sandbox override: explicitly UNSET for this test\n' >> "$REPORT"
printf 'No internet access is requested (local HTML only)\n' >> "$REPORT"

finish() {
    status=$1
    printf 'Result file: %s\n' "$REPORT"
    cat "$REPORT"
    exit "$status"
}

if [ -z "$APP" ] ||
   [ ! -f "$APP/scripts/fire4nix_env.sh" ]; then
    echo 'FAIL: Fire4Nix scripts not found next to this Tools test' >> "$REPORT"
    finish 2
fi
APP="$(CDPATH='' cd -- "$APP" 2>/dev/null && pwd -P)" || finish 2
if [ "$(uname -m 2>/dev/null)" != aarch64 ] &&
   [ "${FIRE4NIX_DEVICE_TEST_ALLOW_NON_ARM64:-0}" != 1 ]; then
    echo 'SKIP: device is not aarch64; R36H test requires ARM64' >> "$REPORT"
    finish 2
fi

if [ "$MODE" = wayland ]; then
    # ROCKNIX/Sway commonly runs on wayland-1. Tools can inherit a stale
    # wayland-0 or no WAYLAND_DISPLAY at all. Prefer an explicitly requested
    # valid socket, then search only known local session runtime directories.
    WAYLAND_SOCKET=""
    if [ -n "${WAYLAND_DISPLAY:-}" ]; then
        case "$WAYLAND_DISPLAY" in
            /*) candidate_socket="$WAYLAND_DISPLAY" ;;
            *) candidate_socket="${XDG_RUNTIME_DIR:-/nonexistent}/$WAYLAND_DISPLAY" ;;
        esac
        if [ -S "$candidate_socket" ]; then WAYLAND_SOCKET="$candidate_socket"; fi
    fi
    if [ -z "$WAYLAND_SOCKET" ]; then
        original_display="${WAYLAND_DISPLAY:-unset}"
        original_runtime="${XDG_RUNTIME_DIR:-unset}"
        uid="$(id -u 2>/dev/null || echo 0)"
        for candidate_dir in \
            "${XDG_RUNTIME_DIR:-/nonexistent}" \
            "/run/user/$uid" \
            /var/run/0-runtime-dir; do
            [ -d "$candidate_dir" ] || continue
            for candidate_socket in "$candidate_dir"/wayland-*; do
                [ -S "$candidate_socket" ] || continue
                WAYLAND_SOCKET="$candidate_socket"
                export XDG_RUNTIME_DIR="$candidate_dir"
                export WAYLAND_DISPLAY="${candidate_socket##*/}"
                echo "Wayland socket recovered: $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY (previous $original_runtime/$original_display)" >> "$REPORT"
                break 2
            done
        done
    fi
    if [ -z "$WAYLAND_SOCKET" ] || [ ! -S "$WAYLAND_SOCKET" ]; then
        echo 'SKIP: no usable Wayland socket found in ROCKNIX session runtime paths' >> "$REPORT"
        finish 2
    fi
    echo "Wayland socket verified: $WAYLAND_SOCKET" >> "$REPORT"
else
    export XDG_RUNTIME_DIR="$RUN/xdg"
    mkdir -p "$XDG_RUNTIME_DIR"
    chmod 700 "$XDG_RUNTIME_DIR"
fi
export FIRE4NIX_RUNTIME_DIR="$RUN/browser-runtime"
export FIRE4NIX_HOME="$APP"
export APP_DIR="$APP"
export WPE_PLATFORM="$MODE"
# A user-provided unsafe diagnostic flag must never leak into a real device test.
unset WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS

cat > "$RUN/local-test.html" <<'HTML'
<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8"><title>Fire4Nix ROCKNIX local smoke</title></head>
<body><h1>Fire4Nix WPE device test</h1><p>Local HTML, sandbox enabled.</p></body></html>
HTML
URL="file://$RUN/local-test.html"

# Invoke native WPE directly after validated bundled-runtime activation.
# Never fall back to Cog: the result must describe the actual WPE engine.
set +e
timeout 45s bash -c '
    source "$APP_DIR/scripts/fire4nix_env.sh"
    native="$(fire4nix_wpe_platform_binary)"
    if [ -z "$native" ]; then
        echo "DEVICE TEST ERROR: native WPE binary not present" >&2
        exit 127
    fi
    fire4nix_wpe_runtime_env
    if ! fire4nix_activate_bundled_wpe_runtime; then
        echo "DEVICE TEST ERROR: bundled runtime preflight failed" >&2
        exit 126
    fi
    if [ "$1" = headless ]; then
        exec "$native" --headless --exit-after-load "$2"
    fi
    exec "$native" --exit-after-load "$2"
' bash "$MODE" "$URL" > "$LAUNCH_LOG" 2>&1
status=$?
set -e
printf 'Browser exit status: %s\n' "$status" >> "$REPORT"
if [ -f "$STATE" ]; then
    cp "$STATE" "$RUN/final-browser.state"
fi
if [ "$status" -eq 0 ] &&
   [ -f "$STATE" ] &&
   grep -q 'Fire4Nix WPE finished:' "$LAUNCH_LOG" &&
   grep -q 'event=load-finished' "$STATE" &&
   grep -q 'loading=0' "$STATE" &&
   ! grep -q 'Fire4Nix WPE load failed' "$LAUNCH_LOG" &&
   { [ "$MODE" = headless ] ||
     grep -q 'Fire4Nix WPE surface:' "$LAUNCH_LOG"; }; then
    echo "PASS: WPE loaded local HTML with sandbox override unset ($MODE)" >> "$REPORT"
    echo 'Hardware test is NOT a complete security audit or release approval.' >> "$REPORT"
    finish 0
fi
if [ "$status" -eq 124 ]; then
    echo 'FAIL: WPE did not complete navigation within 45 seconds' >> "$REPORT"
elif [ "$status" -eq 126 ] || [ "$status" -eq 127 ]; then
    echo 'FAIL: missing/incompatible WPE runtime or executable (see launcher.log)' >> "$REPORT"
else
    echo 'FAIL: WPE did not verify local HTML load with sandbox enabled' >> "$REPORT"
fi
echo 'See launcher.log and final-browser.state (when present) beside this report.' >> "$REPORT"
finish 1
