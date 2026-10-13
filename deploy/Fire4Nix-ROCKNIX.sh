#!/bin/sh
# Fire4Nix ROCKNIX launcher. Safe to invoke from Ports or Tools.
set -u
LOG="${FIRE4NIX_LAUNCH_LOG:-/storage/fire4nix-launch.log}"
[ -d /storage ] && [ -w /storage ] || LOG="${TMPDIR:-/tmp}/fire4nix-launch.log"
APP="${FIRE4NIX_APP_DIR:-/storage/roms/ports/Fire4Nix}"
if [ ! -d "$APP" ]; then
  for candidate in /storage/roms/ports/fire4nix /storage/roms/ports/Fire4nix /storage/roms/ports/navegador-definitivo /storage/roms/tools/Fire4Nix; do
    if [ -f "$candidate/Fire4Nix.sh" ]; then APP="$candidate"; break; fi
  done
fi
(
  echo "=== Fire4Nix $(date) ==="
  echo "arch=$(uname -m) uid=$(id -u) app=$APP"
  if [ ! -f "$APP/Fire4Nix.sh" ]; then
    echo "ERROR: missing $APP/Fire4Nix.sh"
    exit 3
  fi
  if ! command -v bash >/dev/null 2>&1; then
    echo "ERROR: bash unavailable"
    exit 127
  fi
  # Use a writable profile; the ROM partition may be FAT/exFAT.
  export FIRE4NIX_CONFIG_DIR="${FIRE4NIX_CONFIG_DIR:-/storage/.config/fire4nix}"
  export FIRE4NIX_RUNTIME_DIR="${FIRE4NIX_RUNTIME_DIR:-/storage/.cache/fire4nix/runtime}"
  export FIRE4NIX_LOG_DIR="${FIRE4NIX_LOG_DIR:-/storage/.cache/fire4nix/logs}"
  mkdir -p "$FIRE4NIX_CONFIG_DIR" "$FIRE4NIX_RUNTIME_DIR" "$FIRE4NIX_LOG_DIR" || exit 4
  cd "$APP" || exit 5
  bash "$APP/Fire4Nix.sh" "$@"
  rc=$?
  echo "Browser exit code: $rc"
  exit "$rc"
) >>"$LOG" 2>&1
exit $?
