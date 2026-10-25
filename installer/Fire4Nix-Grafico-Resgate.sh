#!/bin/sh
# Fire4Nix / ROCKNIX ARM64: offline graphical recovery and evidence, v2.
# No firmware, graphics-stack, /usr, or native WebKit changes.
set -u
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 2
APP=${FIRE4NIX_ROOT:-$HERE/Fire4Nix}
if [ ! -f "$APP/Fire4Nix-Iniciar.sh" ] && [ -f "$HERE/Fire4Nix-Iniciar.sh" ]; then
    APP=$HERE
fi
MODE=${1:---auto}
case "$MODE" in
    --auto|--normal|--software|--live|--live-software|--live-auto|--diagnose) ;;
    --help)
        printf '%s\n' 'Usage: sh Fire4Nix-Grafico-Resgate.sh [--auto|--normal|--software|--live|--live-software|--live-auto|--diagnose]' \
          '--auto: offline smoke; retry Skia CPU on probable renderer failures (70,71,124,134,139).' \
          '--live-auto: interactive; retry only if the first session fails with a recoverable code.' \
          '--live: default GPU compositor; --live-software: Skia CPU compositor.' \
          '--diagnose: verify WPE library and platform ABI without launching a page.'
        exit 0 ;;
    *) printf 'unsupported_mode=%s\n' "$MODE" >&2; exit 2 ;;
esac
if [ ! -s "$APP/bin/fire4nix-native-aarch64" ] ||
   [ ! -s "$APP/runtime/lib/libWPEWebKit-2.0.so.1" ] ||
   [ ! -s "$APP/runtime/libexec/wpe-webkit-2.0/WPEWebProcess" ] ||
   [ ! -s "$APP/runtime/libexec/wpe-webkit-2.0/WPENetworkProcess" ]; then
    printf 'FIRE4NIX_RESCUE=BLOCKED_MISSING_PACKAGE\nexpected_root=%s\n' "$APP" >&2
    exit 127
fi
if [ ! -s "$APP/www/primeiro-teste.html" ] && [ "$MODE" != --diagnose ]; then
    printf 'FIRE4NIX_RESCUE=BLOCKED_MISSING_OFFLINE_HTML\nexpected_root=%s\n' "$APP" >&2
    exit 127
fi
if ! mkdir -p "$APP/logs" 2>/dev/null || [ ! -w "$APP/logs" ]; then
    LOG_BASE=${TMPDIR:-/tmp}
else
    LOG_BASE="$APP/logs"
fi
LOG="$LOG_BASE/Fire4Nix-Grafico-Resgate-ultimo.txt"
if ! : > "$LOG" 2>/dev/null; then
    printf 'FIRE4NIX_RESCUE=LOG_UNWRITABLE\n' >&2
    exit 73
fi
PAGE="file://$APP/www/primeiro-teste.html"
# The ROCKNIX Mali driver passed EGL_DEFAULT_DISPLAY with native Wayland.
# Users can explicitly set a different display or disable the patched fallback.
if [ -z "${MALI_DEFAULT_DISPLAY+x}" ]; then MALI_DEFAULT_DISPLAY=wayland; fi
if [ -z "${FIRE4NIX_WPE_DEFAULT_EGL+x}" ]; then FIRE4NIX_WPE_DEFAULT_EGL=1; fi
export MALI_DEFAULT_DISPLAY FIRE4NIX_WPE_DEFAULT_EGL
printf 'version=2\nroot=%s\nmode=%s\nnetwork_required=no\n' "$APP" "$MODE" >> "$LOG"
printf 'first_frame_verified=no\nmali_default_display=%s\nwpe_default_egl_fallback=%s\n' \
    "$MALI_DEFAULT_DISPLAY" "$FIRE4NIX_WPE_DEFAULT_EGL" >> "$LOG"
report_copy() {
    if [ -d /storage ] && [ -w /storage ]; then
        cp "$LOG" /storage/Fire4Nix-Grafico-Resgate-ultimo.txt 2>/dev/null || true
    fi
}
run_variant() {
    variant=$1
    flag=$2
    printf '\ntrial=%s native_flag=%s\n' "$variant" "$flag" >> "$LOG"
    if [ "$variant" = software ]; then
        (
            export WEBKIT_SKIA_ENABLE_CPU_RENDERING=1
            sh "$APP/Fire4Nix-Iniciar.sh" "$flag" "$PAGE"
        ) >> "$LOG" 2>&1
        trial_status=$?
    else
        (
            unset WEBKIT_SKIA_ENABLE_CPU_RENDERING
            sh "$APP/Fire4Nix-Iniciar.sh" "$flag" "$PAGE"
        ) >> "$LOG" 2>&1
        trial_status=$?
    fi
    printf 'trial=%s exit=%s\n' "$variant" "$trial_status" >> "$LOG"
    return "$trial_status"
}
classify() {
    case "$1" in
        0) CLASS=success_no_frame_proof; RETRY=no ;;
        69) CLASS=wayland_socket_unavailable; RETRY=no ;;
        126|127) CLASS=missing_or_unexecutable_runtime; RETRY=no ;;
        70) CLASS=webprocess_terminated; RETRY=yes ;;
        71) CLASS=display_disconnected; RETRY=yes ;;
        124) CLASS=page_load_timeout; RETRY=yes ;;
        134) CLASS=process_aborted_sigabrt; RETRY=yes ;;
        139) CLASS=process_crashed_sigsegv; RETRY=yes ;;
        3) CLASS=page_load_failed; RETRY=no ;;
        *) CLASS=other_process_error; RETRY=no ;;
    esac
    if [ "$RETRY" = no ] && [ "$1" -ne 0 ]; then
        case "$1" in
          69|126|127|3) ;;
          *)
            if sed -n "/^trial=$variant native_flag=/,\$p" "$LOG" | \
               grep -Eiq 'Could not create EGL display|EGL_BAD_|EGL.*initializ|web-process-terminated|WPE display disconnected'; then
                CLASS=graphics_signature_in_log
                RETRY=yes
            fi ;;
        esac
    fi
}
status=0
case "$MODE" in
    --diagnose)
        printf 'diagnostic=check_library\n' >> "$LOG"
        sh "$APP/Fire4Nix-Iniciar.sh" --check-library >> "$LOG" 2>&1 || status=$?
        if [ "$status" -eq 0 ]; then
            printf 'diagnostic=check_platform\n' >> "$LOG"
            sh "$APP/Fire4Nix-Iniciar.sh" --check-platform >> "$LOG" 2>&1 || status=$?
        fi
        CLASS=abi_only_no_frame_proof
        RETRY=no ;;
    --normal) run_variant normal --smoke || status=$?; classify "$status" ;;
    --software) run_variant software --smoke || status=$?; classify "$status" ;;
    --live) run_variant normal --open || status=$?; classify "$status" ;;
    --live-software) run_variant software --open || status=$?; classify "$status" ;;
    --auto|--live-auto)
        flag=--smoke
        if [ "$MODE" = --live-auto ]; then flag=--open; fi
        run_variant normal "$flag" || status=$?
        classify "$status"
        printf 'initial_classification=%s\n' "$CLASS" >> "$LOG"
        if [ "$RETRY" = yes ]; then
            printf 'recovery=TRY_SKIA_CPU_AFTER_%s\n' "$CLASS" >> "$LOG"
            status=0
            run_variant software "$flag" || status=$?
            classify "$status"
        else
            printf 'recovery=NOT_RETRIED_%s\n' "$CLASS" >> "$LOG"
        fi ;;
esac
printf 'final_classification=%s\nFIRE4NIX_RESCUE_EXIT=%s\n' "$CLASS" "$status" >> "$LOG"
printf 'GRAPHICAL_HARDWARE_STATUS=UNVERIFIED_UNTIL_VISIBLE_FRAME\n' >> "$LOG"
report_copy
tail -n 55 "$LOG"
printf '\nFULL_REPORT=%s\n' "$LOG"
exit "$status"
