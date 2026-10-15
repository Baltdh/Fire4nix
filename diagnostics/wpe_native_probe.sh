#!/bin/sh
# Fire4Nix independent native WebKit probe. Does not replace the browser.
set -u
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 2
ROOT=${FIRE4NIX_ROOT:-/storage/games-internal/roms/tools/Fire4Nix}
MODE=${1:---check-library}
[ "$#" -eq 0 ] || shift
if [ ! -f "$HERE/fire4nix-wpe-probe-aarch64" ]; then
  echo 'Probe executable not found in the same folder' >&2
  exit 2
fi
if [ ! -d "$ROOT/runtime/lib" ]; then
  echo "WPE runtime directory unavailable: $ROOT" >&2
  exit 2
fi
LOG_DIR=${FIRE4NIX_PROBE_LOG_DIR:-/storage/Fire4Nix-Logs}
if ! mkdir -p "$LOG_DIR" 2>/dev/null; then LOG_DIR="${TMPDIR:-/tmp}"; fi
LOG="$LOG_DIR/wpe-native-probe-$(date +%Y%m%d-%H%M%S 2>/dev/null)-$$.log"
{
  printf '=== Fire4Nix WPE ARM64 native probe ===\n'
  printf 'root=%s\nmode=%s\n' "$ROOT" "$MODE"
  uname -a
  printf 'LD_LIBRARY_PATH=%s\n' "$ROOT/runtime/lib"
  printf 'sandbox remains unchanged\n'
} > "$LOG"
LD_LIBRARY_PATH="$ROOT/runtime/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
WEBKIT_EXEC_PATH="$ROOT/runtime/libexec/wpe-webkit-2.0"
export LD_LIBRARY_PATH WEBKIT_EXEC_PATH
WPE_DISPLAY=${WPE_DISPLAY:-wpe-display-wayland}
WPE_PLATFORM=${WPE_PLATFORM:-wayland}
export WPE_DISPLAY WPE_PLATFORM
if [ "$MODE" = --load ] && [ "$#" -eq 0 ]; then
  set -- "file://$ROOT/www/inicio.html"
fi
"$HERE/fire4nix-wpe-probe-aarch64" "$MODE" "$@" >> "$LOG" 2>&1
STATUS=$?
printf 'native_probe_status=%s\n' "$STATUS" >> "$LOG"
tail -n 80 "$LOG"
if [ -d /storage ] && [ -w /storage ]; then
  cp "$LOG" /storage/Fire4Nix-Sonda-WPE.txt 2>/dev/null || true
fi
exit "$STATUS"
