#!/bin/sh
# Fire4Nix menu entry for ROCKNIX. Never requires root.
# Put this script in the ROMs scripts menu; keep the full app in ports/Fire4Nix.
LOG=/storage/fire4nix-launch.log
APP="${FIRE4NIX_APP_DIR:-/storage/roms/ports/Fire4Nix}"
(
 echo "=== Fire4Nix $(date) ==="
 echo "arch=$(uname -m) uid=$(id -u)"
 echo "app=$APP"
 if [ ! -d "$APP" ]; then echo "ERROR: missing app directory"; exit 2; fi
 if [ ! -f "$APP/scripts/run_browser.sh" ]; then echo "ERROR: missing scripts/run_browser.sh"; exit 3; fi
 if ! command -v bash >/dev/null 2>&1; then echo "ERROR: bash missing"; exit 4; fi
 cd "$APP" || exit 5
 # Files copied from FAT/exFAT may lose executable permissions.
 for f in "$APP/bin/browser.arm64" "$APP/bin/fire4nix-wpe-platform"; do
   [ ! -f "$f" ] || chmod +x "$f" 2>/dev/null || true
 done
 bash "$APP/scripts/run_browser.sh"
 rc=$?
 echo "Browser exit code: $rc"
 exit "$rc"
) >"$LOG" 2>&1
rc=$?
# EmulationStation may close the screen instantly. Log survives reboot.
exit "$rc"
