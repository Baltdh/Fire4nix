#!/usr/bin/env bash
# Exercise the REAL engine entrypoints, not just their helper functions.
# Mock binaries let this run on x86_64 and aarch64 without a graphical session.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
cleanup() {
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "FAIL: engine-entrypoint test returned $rc" >&2
    for f in "$TMP/cog.log" "$TMP/wpe.log" "$TMP/recovery.log" "$TMP/full-entry.log" "$TMP/logs/full-browser.log" "$TMP/full-trace.log" "$TMP/positional-entry.log" "$TMP/failing-entry.log"; do
      if [ -f "$f" ]; then
        echo "--- $f ---" >&2
        cat "$f" >&2
      fi
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/bin" "$TMP/config" "$TMP/runtime" "$TMP/logs"
cat > "$TMP/bin/cog" <<'COG'
#!/bin/sh
printf 'MOCK_COG_ARGS %s\n' "$*"
printf 'MOCK_COG_WAYLAND %s %s\n' "${WAYLAND_DISPLAY:-unset}" "${XDG_RUNTIME_DIR:-unset}"
exit "${MOCK_COG_EXIT_CODE:-0}"
COG
cat > "$TMP/bin/mock-wpe" <<'WPE'
#!/bin/sh
printf 'MOCK_WPE_ARGS %s\n' "$*"
exit "${MOCK_WPE_EXIT_CODE:-0}"
WPE
chmod +x "$TMP/bin/cog" "$TMP/bin/mock-wpe"
export PATH="$TMP/bin:$PATH"
export FIRE4NIX_CONFIG_DIR="$TMP/config"
export FIRE4NIX_RUNTIME_DIR="$TMP/runtime"
export FIRE4NIX_LOG_DIR="$TMP/logs"
export FIRE4NIX_REFERENCE_ROOT="$TMP/nonexistent-reference"
export FIRE4NIX_COG_PLATFORM=wl
export FIRE4NIX_WPE_PLATFORM_BINARY="$TMP/bin/mock-wpe"

bash "$ROOT/navegador-definitivo/scripts/wpe_cog_launch.sh" "https://example.org/cog-entry" > "$TMP/cog.log" 2>&1
grep -q 'MOCK_COG_ARGS' "$TMP/cog.log"
grep -q 'https://example.org/cog-entry' "$TMP/cog.log"

bash "$ROOT/navegador-definitivo/scripts/wpe_platform_launch.sh" "https://example.org/wpe-entry" > "$TMP/wpe.log" 2>&1
grep -q 'MOCK_WPE_ARGS https://example.org/wpe-entry' "$TMP/wpe.log"

MOCK_WPE_EXIT_CODE=42 bash "$ROOT/navegador-definitivo/scripts/wpe_platform_launch.sh" "https://example.org/recovery" > "$TMP/recovery.log" 2>&1
grep -q 'MOCK_WPE_ARGS https://example.org/recovery' "$TMP/recovery.log"
grep -q 'attempting Cog fallback' "$TMP/recovery.log"
grep -q 'MOCK_COG_ARGS' "$TMP/recovery.log"
grep -q 'https://example.org/recovery' "$TMP/recovery.log"
# Create a ROCKNIX-like Wayland socket named wayland-1, with wayland-0
# deliberately misconfigured to check automatic session recovery.
mkdir -p "$TMP/wayland"
python3 - "$TMP/wayland/wayland-1" <<'PY'
import socket, sys
sock = socket.socket(socket.AF_UNIX)
sock.bind(sys.argv[1])
sock.close()
PY
# Execute the full user-facing entrypoint: Fire4Nix.sh -> run_browser.sh ->
# engine resolution -> Cog. This catches unset variables hidden by lower-level
# helper tests, especially under set -u.
if ! FIRE4NIX_ENGINE=cog FIRE4NIX_ENGINE_FILE="$TMP/config/full-engine.conf" \
    XDG_RUNTIME_DIR="$TMP/wayland" WAYLAND_DISPLAY=wayland-0 \
    FIRE4NIX_START_PAGE="https://example.org/full-startup" \
    FIRE4NIX_LOG="$TMP/logs/full-browser.log" \
    FIRE4NIX_ENTRY_LOG="$TMP/full-entry.log" \
    sh "$ROOT/navegador-definitivo/Fire4Nix.sh"; then
    FIRE4NIX_ENGINE=cog FIRE4NIX_ENGINE_FILE="$TMP/config/full-engine.conf" \
        XDG_RUNTIME_DIR="$TMP/wayland" WAYLAND_DISPLAY=wayland-0 \
    FIRE4NIX_START_PAGE="https://example.org/full-startup" \
        FIRE4NIX_LOG="$TMP/logs/full-browser.log" \
        bash -x "$ROOT/navegador-definitivo/scripts/run_browser.sh" > "$TMP/full-trace.log" 2>&1 || true
    exit 1
fi
grep -q 'MOCK_COG_ARGS' "$TMP/full-entry.log"
grep -q 'https://example.org/full-startup' "$TMP/full-entry.log"
grep -q "MOCK_COG_WAYLAND wayland-1 $TMP/wayland" "$TMP/full-entry.log"
grep -q 'recovered Wayland socket: ' "$TMP/logs/full-browser.log"
grep -q 'Exit code: 0' "$TMP/full-entry.log"
grep -q 'launching engine=cog' "$TMP/logs/full-browser.log"
# A user-provided positional URL overrides a preset homepage.
FIRE4NIX_ENGINE=cog FIRE4NIX_ENGINE_FILE="$TMP/config/url-engine.conf" \
    FIRE4NIX_START_PAGE="https://example.org/preset-home" \
    FIRE4NIX_ENTRY_LOG="$TMP/positional-entry.log" \
    sh "$ROOT/navegador-definitivo/Fire4Nix.sh" "https://example.org/explicit-url"
grep -q 'MOCK_COG_ARGS.*https://example.org/explicit-url' "$TMP/positional-entry.log"
if grep -q 'MOCK_COG_ARGS.*https://example.org/preset-home' "$TMP/positional-entry.log"; then
    echo "FAIL: preset homepage replaced explicitly requested URL" >&2
    exit 1
fi

# An engine failure must retain its original code all the way to the user
# entrypoint; a generic status=1 hides the real reason for startup failure.
if MOCK_COG_EXIT_CODE=63 FIRE4NIX_ENGINE=cog \
    FIRE4NIX_ENGINE_FILE="$TMP/config/fail-engine.conf" \
    FIRE4NIX_ENTRY_LOG="$TMP/failing-entry.log" \
    sh "$ROOT/navegador-definitivo/Fire4Nix.sh" "https://example.org/error"; then
    echo "FAIL: failed Cog session unexpectedly succeeded" >&2
    exit 1
else
    status=$?
fi
test "$status" -eq 63
grep -q 'Exit code: 63' "$TMP/failing-entry.log"
# ROCKNIX images may not bundle Python3. The browser must still open local
# HTML files and encode UTF-8 search queries without using that interpreter.
cat > "$TMP/bin/python3" <<'PYTHON'
#!/bin/sh
echo "Unexpected Python3 dependency while normalizing URL" >&2
exit 98
PYTHON
chmod +x "$TMP/bin/python3"
normalize() {
    FIRE4NIX_SEARCH_URL='https://duckduckgo.com/?q=%s' bash -c \
        'APP_DIR="$1"; source "$2"; fire4nix_normalize_target "$3"' \
        bash "$ROOT/navegador-definitivo" \
        "$ROOT/navegador-definitivo/scripts/fire4nix_env.sh" "$1"
}
test "$(normalize 'café & chá')" = 'https://duckduckgo.com/?q=caf%C3%A9+%26+ch%C3%A1'
mkdir -p "$TMP/offline files"
: > "$TMP/offline files/index 1.html"
test "$(normalize "$TMP/offline files/index 1.html")" = "file://$TMP/offline%20files/index%201.html"
printf '%s\n' 'PASS: Cog/WPE, fallback, full launch, Wayland, CLI URL, exit codes and Python-free UTF-8 normalization.'
