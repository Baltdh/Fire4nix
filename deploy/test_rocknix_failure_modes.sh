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
# Native WPE may be present but incompatible with the device's graphics/runtime.
# In that case a fast startup failure must fall back to Cog, rather than close.
mkdir -p "$TMP/mock-bin"
cat > "$TMP/mock-bin/fake-wpe" <<'WPE'
#!/bin/sh
echo MOCK_WPE_STARTUP_FAILURE
exit 42
WPE
cat > "$TMP/mock-bin/cog" <<'COG'
#!/bin/sh
echo MOCK_COG_RECOVERY
exit 0
COG
chmod +x "$TMP/mock-bin/fake-wpe" "$TMP/mock-bin/cog"
env PATH="$TMP/mock-bin:$PATH" FIRE4NIX_WPE_PLATFORM_BINARY="$TMP/mock-bin/fake-wpe" \
    FIRE4NIX_CONFIG_DIR="$TMP/data" FIRE4NIX_RUNTIME_DIR="$TMP/runtime" \
    bash -c 'APP_DIR="$1"; source "$2"; fire4nix_launch_wpe_platform "https://example.org"' \
    bash "$TMP/app" "$ROOT/navegador-definitivo/scripts/fire4nix_env.sh" \
    > "$TMP/native-fallback.log" 2>&1
grep -q MOCK_WPE_STARTUP_FAILURE "$TMP/native-fallback.log"
grep -q 'attempting Cog fallback' "$TMP/native-fallback.log"
grep -q MOCK_COG_RECOVERY "$TMP/native-fallback.log"
# A bundled script with the same name is NOT a native WPE ELF engine.
mkdir -p "$TMP/native-app/bin" "$TMP/native-app/build"
cp "$ROOT/navegador-definitivo/bin/fire4nix-wpe-platform" "$TMP/native-app/bin/fire4nix-wpe-platform"
chmod +x "$TMP/native-app/bin/fire4nix-wpe-platform"
resolved="$(env -u FIRE4NIX_WPE_PLATFORM_BINARY FIRE4NIX_HOME="$TMP/native-app" \
    bash -c 'APP_DIR="$1"; source "$2"; fire4nix_wpe_platform_binary' \
    bash "$TMP/native-app" "$ROOT/navegador-definitivo/scripts/fire4nix_env.sh")"
test -z "$resolved"
# Check both supported native locations, even before any actual ROCKNIX build.
cp /bin/true "$TMP/native-app/fire4nix-wpe-platform"
resolved="$(env -u FIRE4NIX_WPE_PLATFORM_BINARY FIRE4NIX_HOME="$TMP/native-app" \
    bash -c 'APP_DIR="$1"; source "$2"; fire4nix_wpe_platform_binary' \
    bash "$TMP/native-app" "$ROOT/navegador-definitivo/scripts/fire4nix_env.sh")"
test "$resolved" = "$TMP/native-app/fire4nix-wpe-platform"
cp /bin/true "$TMP/native-app/bin/fire4nix-wpe-platform"
resolved="$(env -u FIRE4NIX_WPE_PLATFORM_BINARY FIRE4NIX_HOME="$TMP/native-app" \
    bash -c 'APP_DIR="$1"; source "$2"; fire4nix_wpe_platform_binary' \
    bash "$TMP/native-app" "$ROOT/navegador-definitivo/scripts/fire4nix_env.sh")"
test "$resolved" = "$TMP/native-app/bin/fire4nix-wpe-platform"
echo 'PASS: missing app, recovery, Cog fallback, and native WPE ELF selection without recursive wrappers'
