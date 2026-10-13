#!/bin/sh
# Portable entry point: use Bash explicitly, even on FAT/exFAT copies.
set -u
SCRIPT_DIR="$(CDPATH="" cd -- "$(dirname -- "$0")" && pwd)" || exit 2
LOG="${FIRE4NIX_ENTRY_LOG:-/storage/fire4nix-entry.log}"
if [ ! -d /storage ] || [ ! -w /storage ]; then
  LOG="${TMPDIR:-/tmp}/fire4nix-entry.log"
fi
{
  echo "=== Fire4Nix entry $(date) ==="
  echo "root=$SCRIPT_DIR"
  if ! command -v bash >/dev/null 2>&1; then
    echo "ERROR: Bash unavailable"; exit 127
  fi
  if [ ! -f "$SCRIPT_DIR/scripts/run_browser.sh" ]; then
    echo "ERROR: scripts/run_browser.sh missing"; exit 2
  fi
  cd "$SCRIPT_DIR" || exit 2
  bash "$SCRIPT_DIR/scripts/run_browser.sh" "$@"
  rc=$?
  echo "Exit code: $rc"
  exit "$rc"
} >> "$LOG" 2>&1
