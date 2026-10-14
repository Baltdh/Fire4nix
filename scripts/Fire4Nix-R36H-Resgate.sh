#!/bin/sh
# Fire4Nix R36H/ROCKNIX - isolated WPE runtime recovery and truthful diagnostics.
# Does not modify firmware, /usr, graphics drivers, existing launchers or sandbox settings.
set -u

MODE=stable
ACTION=start
URL=
ROOT="${FIRE4NIX_ROOT:-}"
while [ "$#" -gt 0 ]; do
    case "$1" in
        --check) ACTION=check ;;
        --stable) MODE=stable ;;
        --normal) MODE=normal ;;
        --trace) MODE=trace ;;
        --root) shift; [ "$#" -gt 0 ] || { echo 'Missing --root directory'; exit 2; }; ROOT=$1 ;;
        --url) shift; [ "$#" -gt 0 ] || { echo 'Missing --url value'; exit 2; }; URL=$1 ;;
        -h|--help) echo 'Usage: Fire4Nix-R36H-Resgate.sh [--check] [--stable|--normal|--trace] [--root DIR] [--url URL]'; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

valid_root() { [ -f "$1/bin/fire4nix-wpe-platform" ] && [ -f "$1/runtime/lib/libWPEWebKit-2.0.so.1" ]; }
if [ -n "$ROOT" ] && ! valid_root "$ROOT"; then echo "Invalid Fire4Nix root: $ROOT" >&2; exit 2; fi
if [ -z "$ROOT" ]; then
    SELF=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P) || SELF=.
    for CANDIDATE in \
        "$SELF" "$SELF/Fire4Nix" "$SELF/Tools/Fire4Nix" \
        /storage/games-internal/roms/tools/Fire4Nix \
        /storage/games-external/roms/tools/Fire4Nix \
        /storage/games-external/Download/Fire4Nix \
        /storage/games-internal/roms/tools/*/Tools/Fire4Nix \
        /storage/games-external/Download/*/Tools/Fire4Nix; do
        if valid_root "$CANDIDATE"; then ROOT=$CANDIDATE; break; fi
    done
fi
if [ -z "$ROOT" ]; then
    echo 'Fire4Nix not found. Place this .sh next to its Fire4Nix directory or use --root DIR.' >&2
    exit 2
fi

# Choose a writable user-owned path; no modifications to system libs or directories.
LOG_DIR=${FIRE4NIX_LOG_DIR:-/storage/.local/share/Fire4Nix/logs}
if ! mkdir -p "$LOG_DIR" 2>/dev/null; then
    LOG_DIR="${TMPDIR:-/tmp}/fire4nix-logs"
    mkdir -p "$LOG_DIR" || exit 2
fi
STAMP=$(date +%Y%m%d-%H%M%S 2>/dev/null || echo unknown)
LOG="$LOG_DIR/resgate-$STAMP-$$.log"
SUMMARY="$LOG_DIR/ultimo-diagnostico.txt"
: > "$LOG" || exit 2
log() { printf '%s\n' "$*" | tee -a "$LOG"; }
log '==== Fire4Nix R36H recovery ===='
log "date=$(date 2>/dev/null)"
log "root=$ROOT"
log "mode=$MODE action=$ACTION"
log "uname=$(uname -a 2>/dev/null)"
log "user=$(id -u 2>/dev/null)"

# LD_LIBRARY_PATH is inherited by WPEWebProcess, WPENetworkProcess and WPEGPUProcess.
# Do not substitute libc, libEGL, libGLES or system graphics libraries.
LD_LIBRARY_PATH="$ROOT/runtime/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
WEBKIT_EXEC_PATH="$ROOT/runtime/libexec/wpe-webkit-2.0"
export LD_LIBRARY_PATH WEBKIT_EXEC_PATH
XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/var/run/0-runtime-dir}
WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-1}
if [ ! -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ] && [ -S "$XDG_RUNTIME_DIR/wayland-0" ]; then
    WAYLAND_DISPLAY=wayland-0
fi
export XDG_RUNTIME_DIR WAYLAND_DISPLAY
# ROCKNIX Wayland backend: preserve explicit overrides made by the user.
WPE_PLATFORM=${WPE_PLATFORM:-wayland}
export WPE_PLATFORM

case "$MODE" in
  stable)
    MALI_WAYLAND_AFBC=0
    WEBKIT_SKIA_ENABLE_CPU_RENDERING=1
    WEBKIT_DISABLE_DMABUF_RENDERER=1
    export MALI_WAYLAND_AFBC WEBKIT_SKIA_ENABLE_CPU_RENDERING WEBKIT_DISABLE_DMABUF_RENDERER
    ;;
  trace)
    LD_DEBUG=libs
    export LD_DEBUG
    ;;
esac

log "wayland=$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
log "LD_LIBRARY_PATH=$LD_LIBRARY_PATH"
log "WEBKIT_EXEC_PATH=$WEBKIT_EXEC_PATH"
log "WPE_PLATFORM=$WPE_PLATFORM"
log "binary=$ROOT/bin/fire4nix-wpe-platform"
if [ ! -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]; then
    log 'WARNING: Wayland socket absent; graphical browser cannot launch in this session.'
    [ "$ACTION" = check ] || exit 4
fi
if [ ! -x "$ROOT/bin/fire4nix-wpe-platform" ]; then
    log 'ERROR: native WPE binary is not executable.'
    exit 126
fi
for PROCESS in WPEWebProcess WPENetworkProcess WPEGPUProcess; do
    if [ ! -x "$WEBKIT_EXEC_PATH/$PROCESS" ]; then
        log "ERROR: missing WPE child executable: $WEBKIT_EXEC_PATH/$PROCESS"
        exit 126
    fi
done
if ! command -v bwrap >/dev/null 2>&1; then
    log 'WARNING: bwrap not available. Sandbox compatibility NOT validated; never assume it is enabled.'
fi
if command -v ldd >/dev/null 2>&1; then
    log '-- native library resolution --'
    ldd "$ROOT/bin/fire4nix-wpe-platform" 2>&1 | tee -a "$LOG"
    if ldd "$ROOT/bin/fire4nix-wpe-platform" 2>&1 | grep -q 'not found'; then
        log 'ERROR: native WPE still has unresolved dependencies. Refusing unsafe launch.'
        cp "$LOG" "$SUMMARY" 2>/dev/null || :
        exit 127
    fi
    log '-- WPE engine library resolution --'
    ldd "$ROOT/runtime/lib/libWPEWebKit-2.0.so.1" 2>&1 | tee -a "$LOG"
    if ldd "$ROOT/runtime/lib/libWPEWebKit-2.0.so.1" 2>&1 | grep -q 'not found'; then
        log 'ERROR: WPE runtime has unresolved transitive dependencies.'
        cp "$LOG" "$SUMMARY" 2>/dev/null || :
        exit 127
    fi
fi
[ "$ACTION" = check ] && { log 'CHECK COMPLETED (no graphical execution).'; cp "$LOG" "$SUMMARY" 2>/dev/null || :; exit 0; }

if [ -z "$URL" ]; then
    if [ -f "$ROOT/www/inicio.html" ]; then
        URL="file://$ROOT/www/inicio.html"
    elif [ -f "$ROOT/www/index.html" ]; then
        URL="file://$ROOT/www/index.html"
    else
        log 'ERROR: offline start page absent (www/inicio.html or www/index.html).'
        exit 2
    fi
fi
log "url=$URL"
log 'Starting WPE ...'
"$ROOT/bin/fire4nix-wpe-platform" "$URL" >> "$LOG" 2>&1
RC=$?
log "native_exit_code=$RC"
case "$RC" in
    139) log 'ERROR: native segmentation fault (139) - NOT a Cog error.' ;;
    127) log 'ERROR: loader / executable failed (127); inspect missing symbols/libraries above.' ;;
    0) log 'Native process exited normally (0). This alone does NOT prove page rendered.' ;;
    *) log 'Engine terminated; inspect log for detailed cause.' ;;
esac
# Keep an easily readable text file, including the final lines of the crash log.
{ echo "Fire4Nix: final exit status $RC"; echo "Full log: $LOG"; echo; tail -n 70 "$LOG"; } > "$SUMMARY"
# Secondary optional copy to visible storage for file-manager viewing.
if [ -d /storage ]; then cp "$SUMMARY" /storage/Fire4Nix-ultimo-diagnostico.txt 2>/dev/null || :; fi
printf '\nRecorded in %s\n' "$SUMMARY"
exit "$RC"