#!/bin/sh
# ROCKNIX entry point. Keep this file in the ROMs/scripts menu folder;
# keep the application directory alongside it, not its loose contents.
APP=/storage/roms/ports/Fire4Nix
LOG=/storage/fire4nix-launch.log
{
 echo "=== Fire4Nix $(date) ==="
 echo "uid=$(id -u) arch=$(uname -m) display=${WAYLAND_DISPLAY:-unset}"
 if [ ! -d "$APP" ]; then
   echo "ERROR: missing $APP; copy the complete source/ application folder there"
   exit 2
 fi
 if [ ! -f "$APP/scripts/run_browser.sh" ]; then
   echo "ERROR: missing $APP/scripts/run_browser.sh"
   exit 3
 fi
 if ! command -v bash >/dev/null 2>&1; then
   echo "ERROR: bash not installed"
   exit 4
 fi
 cd "$APP" || exit 5
 bash "$APP/scripts/run_browser.sh"
 rc=$?
 echo "EXIT CODE: $rc"
 exit "$rc"
} >"$LOG" 2>&1
