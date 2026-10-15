#!/bin/sh
# Fire4Nix 0.86 - safe optional native WPEPlatform trial for R36H ROCKNIX.
# No firmware/driver/system file writes. Does not replace old native browser.
set -u
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 2
BIN="$HERE/fire4nix-native-086-aarch64"
ROOT=${FIRE4NIX_ROOT:-}
if [ -z "$ROOT" ]; then
  for folder in /storage/games-internal/roms/tools/Fire4Nix /storage/games-external/roms/tools/Fire4Nix /storage/roms/tools/Fire4Nix; do
    if [ -d "$folder/runtime/lib" ]; then ROOT=$folder; break; fi
  done
fi
if [ ! -f "$BIN" ]; then echo 'ERRO: nao foi encontrado o executavel ARM64 ao lado do script.' >&2; exit 2; fi
if [ -z "$ROOT" ] || [ ! -s "$ROOT/runtime/lib/libWPEWebKit-2.0.so.1" ]; then
  echo 'ERRO: runtime WPE existente nao encontrado. Nao instale bibliotecas em /usr.' >&2
  exit 127
fi
RUNTIME="$ROOT/runtime"
export LD_LIBRARY_PATH="$RUNTIME/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
if [ -d "$RUNTIME/libexec/wpe-webkit-2.0" ]; then
  export WEBKIT_EXEC_PATH="$RUNTIME/libexec/wpe-webkit-2.0"
fi
if [ -z "${XDG_RUNTIME_DIR:-}" ] || [ ! -S "${XDG_RUNTIME_DIR:-/invalid}/${WAYLAND_DISPLAY:-wayland-1}" ]; then
  for dir in /var/run/0-runtime-dir /run/user/0 /run/user/1000; do
    for sock in wayland-1 wayland-0; do
      if [ -S "$dir/$sock" ]; then
        export XDG_RUNTIME_DIR="$dir" WAYLAND_DISPLAY="$sock"
        break 2
      fi
    done
  done
fi
export WPE_PLATFORM=${WPE_PLATFORM:-wayland}
export MALI_WAYLAND_AFBC=${MALI_WAYLAND_AFBC:-0}
export FIRE4NIX_LOW_MEMORY=${FIRE4NIX_LOW_MEMORY:-1}
LOGDIR=${FIRE4NIX_LOG_DIR:-$ROOT/.fire4nix/logs}
mkdir -p "$LOGDIR" 2>/dev/null || LOGDIR=${TMPDIR:-/tmp}
LOG="$LOGDIR/fire4nix-086-$(date +%Y%m%d-%H%M%S 2>/dev/null)-$$.log"
MODE=${1:---smoke}
if [ "$#" -gt 0 ]; then shift; fi
case "$MODE" in
  --selftest|--check-library|--smoke|--open) ;;
  *) echo 'Uso: sh Fire4Nix-086-Teste.sh --check-library|--smoke|--open [URL]' >&2; exit 2 ;;
esac
URL=${1:-}
if [ -z "$URL" ]; then URL="file://$ROOT/www/inicio.html"; fi
printf 'Fire4Nix 0.86 | root=%s | socket=%s/%s | WPE_PLATFORM=%s | modo=%s\n' \
 "$ROOT" "${XDG_RUNTIME_DIR:-unknown}" "${WAYLAND_DISPLAY:-unknown}" "$WPE_PLATFORM" "$MODE" > "$LOG"
case "$MODE" in
  --open) "$BIN" "$URL" >> "$LOG" 2>&1; STATUS=$? ;;
  --smoke) "$BIN" --smoke "$URL" >> "$LOG" 2>&1; STATUS=$? ;;
  --check-library|--selftest) "$BIN" "$MODE" >> "$LOG" 2>&1; STATUS=$? ;;
esac
printf 'real_exit_code=%s\n' "$STATUS" >> "$LOG"
tail -n 85 "$LOG"
if [ -d /storage ] && [ -w /storage ]; then cp "$LOG" /storage/Fire4Nix-086-Resultado.txt 2>/dev/null || true; fi
printf '\nRelatorio: %s\n' "$LOG"
exit "$STATUS"
