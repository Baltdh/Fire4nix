#!/usr/bin/env bash
# Negative and recovery scenarios for the portable ROCKNIX launcher.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/app" "$TMP/data" "$TMP/runtime"
cp "$ROOT/deploy/Fire4Nix-ROCKNIX.sh" "$TMP/app/Start.sh"
chmod +x "$TMP/app/Start.sh"
LOG="$TMP/launch.log"
run() {
  FIRE4NIX_LAUNCH_LOG="$LOG" FIRE4NIX_DATA_ROOT="$TMP/data" \
  XDG_RUNTIME_DIR="$TMP/runtime" WAYLAND_DISPLAY=wayland-1 "$TMP/app/Start.sh"
}
# Missing browser should be a controlled failure, never silent success.
if run; then echo "FAIL: missing app accepted"; exit 1; fi
grep -q 'Fire4Nix.sh not found' "$LOG"
# A browser failure must be propagated and logged.
cat > "$TMP/app/Fire4Nix.sh" <<'APP'
#!/usr/bin/env bash
echo 'MOCK_ENGINE_FAILURE'
exit 42
APP
if run; then echo "FAIL: engine failure accepted"; exit 1; else rc=$?; fi
test "$rc" -eq 42
grep -q 'Browser exit code: 42' "$LOG"
# Browser success should work after a failure without cleanup.
cat > "$TMP/app/Fire4Nix.sh" <<'APP'
#!/usr/bin/env bash
echo 'MOCK_ENGINE_RECOVERED'
exit 0
APP
run
grep -q MOCK_ENGINE_RECOVERED "$LOG"
grep -q 'Browser exit code: 0' "$LOG"
echo 'PASS: missing app, failed engine, recovery and logs'
