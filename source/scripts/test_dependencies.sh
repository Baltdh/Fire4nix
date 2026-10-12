#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/pkg-config" <<'SH'
#!/bin/sh
case "$1" in
  --exists) [ "$2" != "SDL2_net" ];;
  --modversion) printf 'test-version\n';;
  *) exit 2;;
esac
SH
chmod +x "$TMP/pkg-config"
if PKG_CONFIG="$TMP/pkg-config" bash "$ROOT/scripts/check_dependencies.sh" --strict >"$TMP/strict.log" 2>&1; then
  echo "[FAIL] strict mode passed with missing SDL2_net" >&2
  exit 1
fi
if ! grep -q '\[missing\] SDL2_net' "$TMP/strict.log"; then
  cat "$TMP/strict.log"
  echo "[FAIL] missing package not reported" >&2
  exit 1
fi
PKG_CONFIG="$TMP/pkg-config" bash "$ROOT/scripts/check_dependencies.sh" --report >"$TMP/report.log" 2>&1
if ! grep -q '\[error\] 1 required packages missing' "$TMP/report.log"; then
  echo "[FAIL] report mode did not report missing count" >&2
  exit 1
fi
cat > "$TMP/pkg-config" <<'SH'
#!/bin/sh
case "$1" in
  --exists) exit 0;;
  --modversion) printf 'test-version\n';;
  *) exit 2;;
esac
SH
chmod +x "$TMP/pkg-config"
PKG_CONFIG="$TMP/pkg-config" bash "$ROOT/scripts/check_dependencies.sh" --strict >/dev/null
echo "[PASS] dependency checker regression tests"
