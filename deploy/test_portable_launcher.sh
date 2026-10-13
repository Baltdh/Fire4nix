#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
cleanup() {
  result=$?
  if [ "$result" -ne 0 ]; then
    echo "FAIL: portable launcher/ABI test exit code $result" >&2
    for log in "$tmp/diagnostic-report.log" "$tmp/incompatible-report.log" "$tmp/incompatible-console.log"; do
      if [ -f "$log" ]; then
        echo "--- $log ---" >&2
        tail -100 "$log" >&2
      fi
    done
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT
mkdir -p "$tmp/external/downloads/Fire4Nix" "$tmp/data"
cp "$root/deploy/Fire4Nix-ROCKNIX.sh" "$tmp/external/downloads/Fire4Nix/Start.sh"
cat > "$tmp/external/downloads/Fire4Nix/Fire4Nix.sh" <<'EOF'
#!/bin/sh
printf 'PORTABLE_TEST_OK %s\n' "$PWD"
EOF
chmod +x "$tmp/external/downloads/Fire4Nix/Start.sh"
log="$tmp/launch.log"
FIRE4NIX_LAUNCH_LOG="$log" FIRE4NIX_DATA_ROOT="$tmp/data" \
  "$tmp/external/downloads/Fire4Nix/Start.sh"
grep -F 'PORTABLE_TEST_OK' "$log"
grep -F 'Browser exit code: 0' "$log"
ln -s "$tmp/external/downloads/Fire4Nix/Start.sh" "$tmp/shortcut.sh"
FIRE4NIX_LAUNCH_LOG="$log" FIRE4NIX_DATA_ROOT="$tmp/data" "$tmp/shortcut.sh"
test "$(grep -c 'PORTABLE_TEST_OK' "$log")" = 2
mkdir -p "$tmp/override"
cp "$tmp/external/downloads/Fire4Nix/Fire4Nix.sh" "$tmp/override/Fire4Nix.sh"
FIRE4NIX_APP_DIR="$tmp/override" FIRE4NIX_LAUNCH_LOG="$log" FIRE4NIX_DATA_ROOT="$tmp/data" "$tmp/shortcut.sh"
test "$(grep -c 'PORTABLE_TEST_OK' "$log")" = 3
# Exercise the requested ROCKNIX Tools layout, including diagnostic auto-discovery.
mkdir -p "$tmp/Tools/Fire4Nix"
cp "$root/deploy/Fire4Nix-ROCKNIX.sh" "$tmp/Tools/Fire4Nix/Start.sh"
cp "$root/deploy/Fire4Nix-WPE-Diagnostico.sh" "$tmp/Tools/Fire4Nix-WPE-Diagnostico.sh"
cp "$tmp/external/downloads/Fire4Nix/Fire4Nix.sh" "$tmp/Tools/Fire4Nix/Fire4Nix.sh"
chmod +x "$tmp/Tools/Fire4Nix/Start.sh"
FIRE4NIX_LAUNCH_LOG="$log" FIRE4NIX_DATA_ROOT="$tmp/data" "$tmp/Tools/Fire4Nix/Start.sh"
test "$(grep -c 'PORTABLE_TEST_OK' "$log")" -eq 4
env -u FIRE4NIX_APP_DIR FIRE4NIX_DIAGNOSTIC_LOG="$tmp/diagnostic-report.log" \
  sh "$tmp/Tools/Fire4Nix-WPE-Diagnostico.sh" > "$tmp/diagnostic.log"
grep -F "app: $tmp/Tools/Fire4Nix" "$tmp/diagnostic.log"
grep -F "app: $tmp/Tools/Fire4Nix" "$tmp/diagnostic-report.log"
grep -F "Diagnostic saved: $tmp/diagnostic-report.log" "$tmp/diagnostic.log"
test "$(stat -c '%a' "$tmp/diagnostic-report.log")" = 600
# ABI preflight is read-only: simulate a device with too-old glibc and verify
# that it reports incompatible symbol requirements, rather than claiming the
# standalone launcher will run on ROCKNIX.
mkdir -p "$tmp/Tools/Fire4Nix/bin" "$tmp/mock-bin"
printf '%s\n' '{"highest_required_glibc_across_components": "GLIBC_9.99"}' > "$tmp/Tools/WPE-ABI-REQUIREMENTS.json"
cp /bin/true "$tmp/Tools/Fire4Nix/bin/fire4nix-wpe-platform"
cat > "$tmp/mock-bin/getconf" <<'MOCK'
#!/bin/sh
if [ "${1:-}" = GNU_LIBC_VERSION ]; then printf '%s\n' 'glibc 2.0'; else exit 1; fi
MOCK
chmod +x "$tmp/mock-bin/getconf"
PATH="$tmp/mock-bin:$PATH" FIRE4NIX_DIAGNOSTIC_LOG="$tmp/incompatible-report.log" \
  sh "$tmp/Tools/Fire4Nix-WPE-Diagnostico.sh" > "$tmp/incompatible-console.log"
grep -F 'WPE build-origin GLIBC floor: GLIBC_9.99' "$tmp/incompatible-report.log"
grep -F 'INCOMPATIBLE: WPE build requires GLIBC_9.99 but device reports glibc 2.0' "$tmp/incompatible-report.log"
grep -F 'Highest required GLIBC: GLIBC_' "$tmp/incompatible-report.log"
grep -F 'INCOMPATIBLE: binary requires GLIBC_' "$tmp/incompatible-report.log"
grep -F 'WPEWebProcess: NOT FOUND' "$tmp/incompatible-report.log"
echo 'Portable, Tools and ABI compatibility diagnostics passed'
