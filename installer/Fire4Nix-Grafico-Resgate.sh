#!/bin/sh
# Fire4Nix / ROCKNIX ARM64: offline graphical recovery and evidence, v3.
# No firmware, graphics-stack, /usr, or native WebKit changes.
set -u
umask 077
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 2
# An explicit root is authoritative: never silently launch another package.
if [ "${FIRE4NIX_ROOT+x}" = x ]; then
    APP=$FIRE4NIX_ROOT
else
    APP="$HERE/Fire4Nix"
    if [ ! -f "$APP/Fire4Nix-Iniciar.sh" ] && [ -f "$HERE/Fire4Nix-Iniciar.sh" ]; then
        APP=$HERE
    fi
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
if [ -z "$APP" ] || [ ! -f "$APP/Fire4Nix-Iniciar.sh" ] ||
   [ ! -s "$APP/bin/fire4nix-native-aarch64" ] ||
   [ ! -s "$APP/runtime/lib/libWPEWebKit-2.0.so.1" ] ||
   [ ! -s "$APP/runtime/libexec/wpe-webkit-2.0/WPEWebProcess" ] ||
   [ ! -s "$APP/runtime/libexec/wpe-webkit-2.0/WPENetworkProcess" ]; then
    printf 'FIRE4NIX_RESCUE=BLOCKED_MISSING_PACKAGE\nexpected_root=%s\n' "$APP" >&2
    exit 127
fi
APP=$(CDPATH= cd -- "$APP" && pwd -P) || exit 127
# Bound smoke/ABI checks even if native initialization hangs before GLib timers.
# Interactive modes deliberately keep running until the user closes the page.
LIMIT=${FIRE4NIX_RESCUE_TIMEOUT:-30}
case "$LIMIT" in
    ''|*[!0-9]*) printf 'FIRE4NIX_RESCUE=INVALID_TIMEOUT\n' >&2; exit 2 ;;
esac
if [ "${#LIMIT}" -gt 3 ] || [ "$LIMIT" -lt 1 ] || [ "$LIMIT" -gt 300 ]; then
    printf 'FIRE4NIX_RESCUE=INVALID_TIMEOUT\n' >&2
    exit 2
fi
case "$MODE" in
    --live|--live-software|--live-auto) ;;
    *) command -v timeout >/dev/null 2>&1 || {
        printf 'FIRE4NIX_RESCUE=BLOCKED_TIMEOUT_UNAVAILABLE\n' >&2
        exit 127
    } ;;
esac
if [ ! -s "$APP/www/primeiro-teste.html" ] && [ "$MODE" != --diagnose ]; then
    printf 'FIRE4NIX_RESCUE=BLOCKED_MISSING_OFFLINE_HTML\nexpected_root=%s\n' "$APP" >&2
    exit 127
fi
if ! mkdir -p "$APP/logs" 2>/dev/null || [ ! -w "$APP/logs" ]; then
    LOG_BASE=${TMPDIR:-/tmp}
else
    LOG_BASE="$APP/logs"
fi
LOG=$(mktemp "$LOG_BASE/Fire4Nix-Grafico-Resgate-log-XXXXXX") || {
    printf 'FIRE4NIX_RESCUE=LOG_UNWRITABLE\n' >&2
    exit 73
}
# Percent-encode reserved URI characters in the SD mount path.
URI_PATH=$(printf '%s' "$APP/www/primeiro-teste.html" | sed -e 's/%/%25/g' -e 's/ /%20/g' -e 's/#/%23/g' -e 's/?/%3F/g')
PAGE="file://$URI_PATH"
# The ROCKNIX Mali driver passed EGL_DEFAULT_DISPLAY with native Wayland.
# Users can explicitly set a different display or disable the patched fallback.
if [ -z "${MALI_DEFAULT_DISPLAY+x}" ]; then MALI_DEFAULT_DISPLAY=wayland; fi
if [ -z "${FIRE4NIX_WPE_DEFAULT_EGL+x}" ]; then FIRE4NIX_WPE_DEFAULT_EGL=1; fi
export MALI_DEFAULT_DISPLAY FIRE4NIX_WPE_DEFAULT_EGL
printf 'version=3\nroot=%s\nmode=%s\nnetwork_required=no\n' "$APP" "$MODE" >> "$LOG"
printf 'first_frame_verified=no\nmali_default_display=%s\nwpe_default_egl_fallback=%s\n' \
    "$MALI_DEFAULT_DISPLAY" "$FIRE4NIX_WPE_DEFAULT_EGL" >> "$LOG"
publish_report() {
    destination=$1
    snapshot=$(mktemp "$(dirname "$destination")/.fire4nix-rescue-report-XXXXXX") || return 1
    if cp "$LOG" "$snapshot" && mv -f "$snapshot" "$destination"; then
        return 0
    fi
    rm -f "$snapshot"
    return 1
}
report_copy() {
    # Publish a complete snapshot; concurrent sessions keep independent evidence.
    publish_report "$LOG_BASE/Fire4Nix-Grafico-Resgate-ultimo.txt" || true
    if [ -d /storage ] && [ -w /storage ]; then
        publish_report /storage/Fire4Nix-Grafico-Resgate-ultimo.txt || true
    fi
}
launch_native() {
    if [ "$1" = --open ]; then
        sh "$APP/Fire4Nix-Iniciar.sh" "$@"
    else
        timeout "$LIMIT" sh "$APP/Fire4Nix-Iniciar.sh" "$@"
    fi
}
run_variant() {
    variant=$1
    flag=$2
    printf '\ntrial=%s native_flag=%s\n' "$variant" "$flag" >> "$LOG"
    # Native WebKit messages are in a second log. Capture the whole log,
    # not just the last 40 lines printed by the launcher on exit.
    attempt_dir=$(mktemp -d "$LOG_BASE/Fire4Nix-EGL-attempt-XXXXXX") || {
        printf 'error=unable_to_create_native_log_dir\n' >> "$LOG"
        return 73
    }
    if [ "$variant" = software ]; then
        (
            export FIRE4NIX_LOG_DIR="$attempt_dir"
            export WEBKIT_SKIA_ENABLE_CPU_RENDERING=1
            launch_native "$flag" "$PAGE"
        ) >> "$LOG" 2>&1
        trial_status=$?
    else
        (
            export FIRE4NIX_LOG_DIR="$attempt_dir"
            unset WEBKIT_SKIA_ENABLE_CPU_RENDERING
            launch_native "$flag" "$PAGE"
        ) >> "$LOG" 2>&1
        trial_status=$?
    fi
    for native_log in "$attempt_dir"/Fire4Nix-*-log-*; do
        [ -f "$native_log" ] && [ ! -L "$native_log" ] || continue
        printf 'native_log_captured=%s\n' "$(basename "$native_log")" >> "$LOG"
        cat "$native_log" >> "$LOG"
        rm -f "$native_log"
    done
    rmdir "$attempt_dir" 2>/dev/null || true
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
        130|143) CLASS=interrupted; RETRY=no ;;
        137) CLASS=killed_sigkill; RETRY=no ;;
        *) CLASS=other_process_error; RETRY=no ;;
    esac
    if [ "$RETRY" = no ] && [ "$1" -ne 0 ]; then
        case "$1" in
          69|126|127|3|130|137|143) ;;
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
        launch_native --check-library >> "$LOG" 2>&1 || status=$?
        if [ "$status" -eq 0 ]; then
            printf 'diagnostic=check_platform\n' >> "$LOG"
            launch_native --check-platform >> "$LOG" 2>&1 || status=$?
        fi
        if [ "$status" -eq 0 ]; then
            CLASS=abi_only_no_frame_proof
        else
            variant=diagnostic
            classify "$status"
            CLASS=diagnostic_failed_$CLASS
        fi
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
