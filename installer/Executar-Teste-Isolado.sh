#!/bin/sh
# Run only the package beside this entry. Never reuse an older Ports kit.
set -eu
export LC_ALL=C LANG=C
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 2
cd "$HERE"
MODE=${1:---auto}
case "$MODE" in
    --auto|--normal|--software|--diagnose|--egl|--live|--live-software) ;;
    *) echo 'Use --auto, --normal, --software, --diagnose, --egl, --live or --live-software' >&2; exit 2 ;;
esac
[ "$(uname -m)" = aarch64 ] || { echo 'TEST_BLOCKED=requires_aarch64' >&2; exit 126; }
command -v sha256sum >/dev/null 2>&1 || { echo 'TEST_BLOCKED=sha256sum_missing' >&2; exit 127; }
[ -s PACOTE-SHA256SUMS.txt ] || { echo 'TEST_BLOCKED=manifest_missing' >&2; exit 127; }
# Verify before granting execute permission or loading any native component.
if ! sha256sum -c PACOTE-SHA256SUMS.txt > /dev/null; then
    echo 'TEST_BLOCKED=package_checksum_failed_extract_again' >&2
    exit 65
fi
echo 'PACKAGE_CHECKSUMS=PASS'
export FIRE4NIX_ROOT="$HERE/Fire4Nix"
chmod +x "$FIRE4NIX_ROOT/bin/fire4nix-native-aarch64" \
    "$FIRE4NIX_ROOT/runtime/libexec/wpe-webkit-2.0/WPEWebProcess" \
    "$FIRE4NIX_ROOT/runtime/libexec/wpe-webkit-2.0/WPENetworkProcess"
if [ "$MODE" = --egl ]; then
    command -v python3 >/dev/null 2>&1 || { echo 'TEST_BLOCKED=python3_missing' >&2; exit 127; }
    command -v timeout >/dev/null 2>&1 || { echo 'TEST_BLOCKED=timeout_missing' >&2; exit 127; }
    # Use the device EGL stack for this independent offscreen context probe.
    # Keep an explicitly selected display; otherwise use the observed R36H socket.
    export MALI_DEFAULT_DISPLAY=wayland
    export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/var/run/0-runtime-dir}
    export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-1}
    mkdir -p "$FIRE4NIX_ROOT/logs"
    LOG=$(mktemp "$FIRE4NIX_ROOT/logs/EGL-probe-XXXXXX")
    status=0
    timeout 15 python3 "$HERE/Fire4Nix-EGL-R36H.py" > "$LOG" 2>&1 || status=$?
    cat "$LOG"
    printf 'EGL_PROBE_EXIT=%s\nFULL_REPORT=%s\n' "$status" "$LOG"
    exit "$status"
fi
exec sh "$HERE/Fire4Nix-Grafico-Resgate.sh" "$MODE"
