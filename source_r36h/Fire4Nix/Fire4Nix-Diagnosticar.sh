#!/bin/sh
# Fire4Nix R36H 0.85: launcher/loader diagnostic with optional real graphical test.
# No root, firmware modifications, package installs or sandbox overrides.
set -u
MODE=check
PROFILE=normal
ROOT=${FIRE4NIX_ROOT:-}
URL=${FIRE4NIX_START_PAGE:-}
while [ "$#" -gt 0 ]; do
  case "$1" in
    --check) MODE=check ;;
    --launch) MODE=launch ;;
    --headless) MODE=headless ;;
    --safe) PROFILE=safe ;;
    --root) shift; [ "$#" -gt 0 ] || exit 2; ROOT=$1 ;;
    --url) shift; [ "$#" -gt 0 ] || exit 2; URL=$1 ;;
    --help|-h) echo 'Use: Fire4Nix-Diagnosticar.sh [--check|--launch|--headless] [--safe] [--root DIR] [--url URI]'; exit 0 ;;
    *) echo "Unknown parameter: $1" >&2; exit 2 ;;
  esac
  shift
done
SELF=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 2
if [ -z "$ROOT" ]; then
  for DIR in "$SELF" "$SELF/Tools/Fire4Nix" "$SELF/../Fire4Nix" /storage/games-internal/roms/tools/Fire4Nix /storage/games-external/roms/tools/Fire4Nix; do
    if [ -f "$DIR/bin/fire4nix-wpe-platform" ] || [ -f "$DIR/scripts/run_browser.sh" ]; then ROOT=$DIR; break; fi
  done
fi
if [ -z "$ROOT" ] || [ ! -d "$ROOT" ]; then
  echo 'Fire4Nix folder not detected. Use --root /path/to/Fire4Nix' >&2; exit 2
fi
ROOT=$(CDPATH= cd -- "$ROOT" && pwd -P) || exit 2
if [ -n "${FIRE4NIX_LOG_DIR:-}" ]; then
  LOG_DIR=$FIRE4NIX_LOG_DIR
elif [ -d /storage ] && [ -w /storage ]; then
  LOG_DIR=/storage/Fire4Nix-Logs
else
  LOG_DIR=$ROOT/.fire4nix/logs
fi
if ! mkdir -p "$LOG_DIR" 2>/dev/null || [ ! -w "$LOG_DIR" ]; then
  LOG_DIR=${TMPDIR:-/tmp}/Fire4Nix-Logs
  mkdir -p "$LOG_DIR" || exit 2
fi
STAMP=$(date +%Y%m%d-%H%M%S 2>/dev/null || echo undated)
LOG="$LOG_DIR/r36h-$MODE-$STAMP-$$.log"
LATEST="$LOG_DIR/ultimo-diagnostico.txt"
: > "$LOG" || exit 2
say() { printf '%s\n' "$*" | tee -a "$LOG"; }
finish() {
  STATUS=$1
  {
    printf 'Fire4Nix R36H diagnostic - 0.85\n'
    printf 'mode=%s profile=%s exit_status=%s\n' "$MODE" "$PROFILE" "$STATUS"
    printf 'full_log=%s\n\n' "$LOG"
    tail -n 120 "$LOG"
  } > "$LATEST" 2>/dev/null || true
  if [ -d /storage ] && [ -w /storage ]; then
    cp "$LATEST" /storage/Fire4Nix-relatorio-ultimo.txt 2>/dev/null || true
  fi
  printf 'Diagnostic text: %s\n' "$LATEST"
  exit "$STATUS"
}
log_command() {
  say "> $*"
  "$@" >> "$LOG" 2>&1
  RET=$?
  say "command_exit=$RET"
  return "$RET"
}
say '=== Fire4Nix 0.85 / ROCKNIX R36H ==='
say "run=$(date 2>/dev/null || true)"
say "mode=$MODE profile=$PROFILE"
say "root=$ROOT"
say "system=$(uname -smr 2>/dev/null || echo unknown)"
say "pwd=$(pwd 2>/dev/null || echo unknown)"
BIN="$ROOT/bin/fire4nix-wpe-platform"
LIB="$ROOT/runtime/lib/libWPEWebKit-2.0.so.1"
CHILD="$ROOT/runtime/libexec/wpe-webkit-2.0"
PRECHECK=0
if [ ! -f "$BIN" ]; then say "FAIL: no native launcher $BIN"; PRECHECK=127
elif [ ! -x "$BIN" ]; then say "FAIL: native launcher not executable $BIN"; PRECHECK=126
else say "OK: binary $BIN"; fi
if [ ! -s "$LIB" ]; then say "FAIL: native WPE WebKit library absent/empty: $LIB"; PRECHECK=127
else
  say "OK: WPE WebKit library ($(/usr/bin/stat -c %s "$LIB" 2>/dev/null || wc -c < "$LIB") bytes)"
fi
for PROCESS in WPEWebProcess WPENetworkProcess WPEGPUProcess; do
  if [ ! -x "$CHILD/$PROCESS" ]; then
    say "FAIL: child process missing/non-executable: $PROCESS"
    PRECHECK=126
  else say "OK: child process $PROCESS"; fi
done
if command -v bwrap >/dev/null 2>&1; then say "bubblewrap=$(command -v bwrap)"; else say 'WARNING: bwrap absent; WebKit sandbox not verified'; fi
RUNTIME=${XDG_RUNTIME_DIR:-}
DISPLAY=${WAYLAND_DISPLAY:-}
case "$RUNTIME/$DISPLAY" in
  /|*/)
    ;;
  *) if [ -S "$RUNTIME/$DISPLAY" ]; then say "Wayland socket found: $RUNTIME/$DISPLAY"; fi ;;
esac
if [ -z "$RUNTIME" ] || [ -z "$DISPLAY" ] || [ ! -S "$RUNTIME/$DISPLAY" ]; then
  for TEST_DIR in "$RUNTIME" /var/run/0-runtime-dir /run/user/0; do
    [ -d "$TEST_DIR" ] || continue
    for NAME in wayland-1 wayland-0; do
      if [ -S "$TEST_DIR/$NAME" ]; then RUNTIME=$TEST_DIR; DISPLAY=$NAME; break 2; fi
    done
  done
fi
if [ -n "$RUNTIME" ] && [ -n "$DISPLAY" ] && [ -S "$RUNTIME/$DISPLAY" ]; then
  XDG_RUNTIME_DIR=$RUNTIME; WAYLAND_DISPLAY=$DISPLAY
  export XDG_RUNTIME_DIR WAYLAND_DISPLAY
  say "wayland_selected=$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
else
  say 'WARNING: no usable Wayland socket detected in this shell session'
fi
export LD_LIBRARY_PATH="$ROOT/runtime/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export WEBKIT_EXEC_PATH="$CHILD"
# WPE 2.52 uses WPE_DISPLAY; 2.54 uses WPE_PLATFORM. Setting both supports either.
WPE_PLATFORM=${WPE_PLATFORM:-wayland}
WPE_DISPLAY=${WPE_DISPLAY:-wpe-display-wayland}
export WPE_PLATFORM WPE_DISPLAY
say "WPE_PLATFORM=$WPE_PLATFORM WPE_DISPLAY=$WPE_DISPLAY"
say "WEBKIT_EXEC_PATH=$WEBKIT_EXEC_PATH"
say "LD_LIBRARY_PATH=$LD_LIBRARY_PATH"
if [ "$PROFILE" = safe ]; then
  export MALI_WAYLAND_AFBC=0
  export WEBKIT_DISABLE_DMABUF_RENDERER=1
  export WEBKIT_SKIA_ENABLE_CPU_RENDERING=1
  export FIRE4NIX_LOW_MEMORY=1
  say 'profile: conservative rendering flags; sandbox unchanged'
fi
if command -v file >/dev/null 2>&1 && [ -f "$BIN" ]; then log_command file "$BIN" || true; fi
if command -v readelf >/dev/null 2>&1 && [ -f "$BIN" ]; then
  say '--- ELF architecture and direct dependencies ---'
  readelf -h "$BIN" 2>&1 | grep -E 'Class:|Machine:' >> "$LOG" || true
  readelf -d "$BIN" 2>&1 | grep -E 'NEEDED|RPATH|RUNPATH' >> "$LOG" || true
fi
if command -v ldd >/dev/null 2>&1 && [ -s "$LIB" ] && [ -f "$BIN" ]; then
  say '--- linker resolution for launcher ---'
  ldd "$BIN" >> "$LOG" 2>&1
  if grep -q -E '(not found|version .* not found|undefined symbol)' "$LOG"; then
    say 'FAIL: dynamic loader reports an unresolved library/version/symbol'
    PRECHECK=127
  fi
fi
if [ "$PRECHECK" -ne 0 ]; then finish "$PRECHECK"; fi
if [ "$MODE" = check ]; then
  say 'CHECK_OK: binary and runtime files present; ELF and display reported; WebKit NOT executed'
  finish 0
fi
if [ -z "$URL" ]; then URL="file://$ROOT/www/inicio.html"; fi
if [ "$MODE" = launch ]; then
  if [ -z "$RUNTIME" ] || [ -z "$DISPLAY" ] || [ ! -S "$RUNTIME/$DISPLAY" ]; then
    say 'FAIL: graphical Wayland test has no compositor socket'
    finish 4
  fi
  FIRE4NIX_START_PAGE=$URL
  FIRE4NIX_ENGINE=wpe-platform
  FIRE4NIX_LOG_DIR=$LOG_DIR
  export FIRE4NIX_START_PAGE FIRE4NIX_ENGINE FIRE4NIX_LOG_DIR
  say "START graphical launcher URL=$URL"
  bash "$ROOT/scripts/run_browser.sh" >> "$LOG" 2>&1
  STATUS=$?
else
  if ! command -v timeout >/dev/null 2>&1; then
    say 'FAIL: timeout utility absent; refusing unbounded headless test'
    finish 2
  fi
  WPE_PLATFORM=headless
  WPE_DISPLAY=wpe-display-headless
  export WPE_PLATFORM WPE_DISPLAY
  say "START headless native WPE URL=$URL (30 seconds maximum)"
  timeout 30 "$BIN" "$URL" >> "$LOG" 2>&1
  STATUS=$?
  if [ "$STATUS" -eq 124 ]; then
    say 'TIMEOUT: no native exit/crash in 30s; NOT proof a page loaded'
  fi
fi
say "native_or_launcher_exit=$STATUS"
case "$STATUS" in
  139) say 'CLASSIFICATION: native SIGSEGV; check WebKit/EGL/backend and request backtrace' ;;
  127) say 'CLASSIFICATION: missing loader dependency or executable' ;;
  124) say 'CLASSIFICATION: timed headless probe without normal exit' ;;
  0) say 'CLASSIFICATION: clean exit; page rendering still needs visual confirmation' ;;
  *) say 'CLASSIFICATION: nonzero exit; inspect full diagnostic log' ;;
esac
finish "$STATUS"