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
    for f in "$TMP/cog.log" "$TMP/wpe.log" "$TMP/recovery.log"; do
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
printf '%s\n' 'PASS: Cog/WPE scripts call the Bash engine function, native WPE starts and Cog recovers from fast failure.'
