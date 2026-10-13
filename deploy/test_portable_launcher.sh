#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
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
echo 'Portable, symlink and override launcher tests passed'
