#!/bin/sh
# Fire4Nix R36H 1.05: preserve diagnosis from the very first failing preflight.
set -u
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 2
BIN="$ROOT/bin/fire4nix-native-aarch64"
LOG_DIR=${FIRE4NIX_LOG_DIR:-$ROOT/logs}
if ! mkdir -p "$LOG_DIR" 2>/dev/null || [ ! -w "$LOG_DIR" ]; then
    LOG_DIR=${TMPDIR:-/tmp}
fi
# mktemp avoids collisions between simultaneous sessions without relying on
# process-ID expansion or synchronized handheld clocks.
LOG=$(mktemp "$LOG_DIR/Fire4Nix-$(date +%Y%m%d-%H%M%S)-log-XXXXXX") || {
    echo "Fire4Nix: unable to allocate unique diagnostic log" >&2
    exit 73
}
GAMEPAD_PID=""
stop_gamepad() {
    [ -n "$GAMEPAD_PID" ] || return 0
    # We only stop our own child, never a system-wide hotkey service.
    kill "$GAMEPAD_PID" 2>/dev/null || true
    wait "$GAMEPAD_PID" 2>/dev/null || true
    GAMEPAD_PID=""
}
start_gamepad() {
    [ "$MODE" = --open ] || return 0
    if [ "${FIRE4NIX_GAMEPAD:-auto}" = 0 ]; then
        echo "gamepad=disabled_by_user" >> "$LOG"
        return 0
    fi
    cfg="$ROOT/config/fire4nix.gptk"
    if [ ! -s "$cfg" ]; then
        echo "gamepad=no_controller_profile" >> "$LOG"
        return 0
    fi
    keybin=${FIRE4NIX_GPTOKEYB:-}
    if [ -z "$keybin" ]; then
        keybin=$(command -v gptokeyb 2>/dev/null || true)
    fi
    if [ -z "$keybin" ]; then
        for candidate in /usr/bin/gptokeyb /usr/local/bin/gptokeyb /usr/sbin/gptokeyb; do
            if [ -x "$candidate" ]; then keybin="$candidate"; break; fi
        done
    fi
    if [ -z "$keybin" ] || [ ! -x "$keybin" ]; then
        echo "gamepad=gptokeyb_missing_or_not_executable" >> "$LOG"
        return 0
    fi
    if command -v pgrep >/dev/null 2>&1 && pgrep -x gptokeyb >/dev/null 2>&1; then
        echo "gamepad=skipped_existing_gptokeyb_to_avoid_duplicate_events" >> "$LOG"
        return 0
    fi
    # Do not use gptokeyb -k/-1: those options can kill an unrelated process.
    "$keybin" -c "$cfg" >> "$LOG" 2>&1 &
    GAMEPAD_PID=$!
    # A successful fork is not proof that gptokeyb can access SDL/uinput.
    # Give it a short scheduling opportunity, then capture immediate failures.
    sleep 0.15
    if ! kill -0 "$GAMEPAD_PID" 2>/dev/null; then
        helper_exit=0
        wait "$GAMEPAD_PID" 2>/dev/null || helper_exit=$?
        printf 'gamepad=helper_exited_early exit_code=%s\n' "$helper_exit" >> "$LOG"
        GAMEPAD_PID=""
        return 0
    fi
    printf 'gamepad=running pid=%s config=%s\n' "$GAMEPAD_PID" "$cfg" >> "$LOG"
}

if ! : > "$LOG" 2>/dev/null; then
    echo "Fire4Nix: cannot create diagnostic log under $LOG_DIR" >&2
    exit 73
fi
finish() {
    code=$?
    trap - 0
    stop_gamepad
    printf 'fire4nix_exit_code=%s\n' "$code" >> "$LOG"
    if [ -d /storage ] && [ -w /storage ]; then
        cp "$LOG" /storage/Fire4Nix-ultimo-resultado.txt 2>/dev/null || true
    fi
    tail -n 40 "$LOG" 2>/dev/null || true
    exit "$code"
}
trap finish 0
trap 'exit 130' INT
trap 'exit 143' TERM
fail() {
    code=$1
    shift
    printf 'Fire4Nix: %s\n' "$*" >&2
    printf 'error=%s\n' "$*" >> "$LOG"
    exit "$code"
}
# At most 12 log files; never delete the stable last-result copy in /storage.
ls -1t "$LOG_DIR"/Fire4Nix-*.log "$LOG_DIR"/Fire4Nix-*-log-* 2>/dev/null | sed -n '13,$p' |
while IFS= read -r old; do
    [ -f "$old" ] && rm -f "$old"
done
printf 'version=1.05\nroot=%s\n' "$ROOT" >> "$LOG"
MODE=--open
case "${1:-}" in
  --open|--smoke|--headless|--check-library|--check-platform|--selftest|--verify-offline)
    MODE=$1
    shift ;;
  --*) fail 2 "Unsupported Fire4Nix option: $1" ;;
esac
printf 'mode=%s\n' "$MODE" >> "$LOG"
[ -f "$BIN" ] || fail 127 "Missing Fire4Nix ARM64 executable"
[ -x "$BIN" ] || chmod u+x "$BIN" 2>/dev/null || true
[ -x "$BIN" ] || fail 126 "ELF cannot execute (permissions/noexec)"
if [ "$MODE" = --selftest ]; then
    "$BIN" --selftest >> "$LOG" 2>&1
    exit $?
fi
LIB="$ROOT/runtime/lib/libWPEWebKit-2.0.so.1"
CHILD="$ROOT/runtime/libexec/wpe-webkit-2.0"
[ -s "$LIB" ] || fail 127 "Missing local WPE WebKit runtime"
# Stage-WPE from ROCKNIX (PR #116) records a verified configure profile.
# Legacy runtimes with no BUILD-REPORT continue to require WPEGPUProcess.
GPU_PROCESS_REQUIRED=1
GPU_REPORT="$ROOT/runtime/BUILD-REPORT.txt"
if [ -e "$GPU_REPORT" ]; then
    [ -f "$GPU_REPORT" ] && [ ! -L "$GPU_REPORT" ] ||
        fail 127 "Invalid WPE runtime build report"
    gpu_evidence=$(sed -n 's/^GPU_PROCESS_PROFILE=//p' "$GPU_REPORT")
    case "$gpu_evidence" in
        disabled_verified_wayland) GPU_PROCESS_REQUIRED=0 ;;
        required_unverified|enabled_verified|'') GPU_PROCESS_REQUIRED=1 ;;
        *) fail 127 "Invalid or conflicting WPE GPU process profile" ;;
    esac
fi
for child in WPEWebProcess WPENetworkProcess; do
    [ -s "$CHILD/$child" ] || fail 127 "Missing WebKit subprocess: $child"
done
if [ "$GPU_PROCESS_REQUIRED" -eq 1 ]; then
    [ -s "$CHILD/WPEGPUProcess" ] || fail 127 "Missing WebKit subprocess: WPEGPUProcess"
fi
printf 'gpu_process_required=%s\n' "$GPU_PROCESS_REQUIRED" >> "$LOG"
# A previous PortMaster/SD launch can leave incompatible system libraries on
# LD_LIBRARY_PATH. Default to the selected Fire4Nix runtime only. Keep the
# previous behavior behind an explicit opt-in for controlled comparisons.
if [ "${FIRE4NIX_INHERIT_LIBRARY_PATH:-0}" = 1 ]; then
    printf 'library_path_mode=compat_inherited\n' >> "$LOG"
    export LD_LIBRARY_PATH="$ROOT/runtime/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
else
    if [ -n "${LD_LIBRARY_PATH:-}" ]; then
        printf 'library_path_mode=isolated_discarded_inherited_paths\n' >> "$LOG"
    else
        printf 'library_path_mode=isolated_no_inherited_paths\n' >> "$LOG"
    fi
    export LD_LIBRARY_PATH="$ROOT/runtime/lib"
fi
# Do not unset LD_PRELOAD: ROCKNIX may use a platform-provided Mali hook.
for lib in libc.so.6 ld-linux-aarch64.so.1 libwayland-client.so.0 \
           libgbm.so.1 libdrm.so.2 libEGL.so.1 libGLESv2.so.2 libmali.so; do
    if [ -e "$ROOT/runtime/lib/$lib" ]; then
        printf 'warning=private_system_or_gpu_library:%s\n' "$lib" >> "$LOG"
    fi
done
export WEBKIT_EXEC_PATH="$CHILD"
# Patched WPE keeps normal EGL paths first, then permits the device-probed
# EGL_DEFAULT_DISPLAY fallback. Unpatched upstream ignores this variable.
export FIRE4NIX_WPE_DEFAULT_EGL=${FIRE4NIX_WPE_DEFAULT_EGL:-1}
printf 'wpe_default_egl_fallback=%s\n' "$FIRE4NIX_WPE_DEFAULT_EGL" >> "$LOG"
# WPE 2.54.1 looks for its dlopen-loaded injected bundle and GResource via
# these exact variables. A private SD-card runtime must not inherit values
# from another WebKit installation or fall back to build-time /usr paths.
INJECTED_DIR="$ROOT/runtime/lib/wpe-webkit-2.0/injected-bundle"
INJECTED_SO="$INJECTED_DIR/libWPEInjectedBundle.so"
INSPECTOR_RESOURCE="$ROOT/runtime/share/wpe-webkit-2.0/inspector.gresource"
ASSET_PROFILE=legacy_optional
ASSET_STATUS=unreported
if [ -f "$GPU_REPORT" ]; then
    declared_profile=$(sed -n 's/^WPE_INSTALLED_ASSETS_PROFILE=//p' "$GPU_REPORT")
    declared_status=$(sed -n 's/^WPE_INSTALLED_ASSETS_STATUS=//p' "$GPU_REPORT")
    case "$declared_profile" in
        '') ;;
        optional|strict) ASSET_PROFILE=$declared_profile ;;
        *) fail 127 "Invalid or conflicting WPE installed-assets profile" ;;
    esac
    case "$declared_status" in
        '') ;;
        not_installed|copied_and_static_elf_checked) ASSET_STATUS=$declared_status ;;
        *) fail 127 "Invalid or conflicting WPE installed-assets status" ;;
    esac
fi
if [ "$ASSET_PROFILE" = strict ] &&
   [ "$ASSET_STATUS" != copied_and_static_elf_checked ]; then
    fail 127 "Strict WPE runtime assets were not verified during staging"
fi
if [ -e "$INJECTED_DIR" ] || [ -L "$INJECTED_DIR" ] ||
   [ -e "$INJECTED_SO" ] || [ -L "$INJECTED_SO" ] ||
   [ -e "$INSPECTOR_RESOURCE" ] || [ -L "$INSPECTOR_RESOURCE" ]; then
    [ -d "$INJECTED_DIR" ] && [ ! -L "$INJECTED_DIR" ] &&
    [ -s "$INJECTED_SO" ] && [ -f "$INJECTED_SO" ] && [ ! -L "$INJECTED_SO" ] &&
    [ -s "$INSPECTOR_RESOURCE" ] && [ -f "$INSPECTOR_RESOURCE" ] &&
    [ ! -L "$INSPECTOR_RESOURCE" ] ||
        fail 127 "WPE injected-bundle or inspector resource missing/unsafe"
    [ "$ASSET_STATUS" != not_installed ] ||
        fail 127 "WPE installed-assets report conflicts with packaged files"
    export WEBKIT_INJECTED_BUNDLE_PATH="$INJECTED_DIR"
    export WEBKIT_INSPECTOR_RESOURCES_PATH="$INSPECTOR_RESOURCE"
    printf 'wpe_installed_assets=private_verified_path profile=%s\n' "$ASSET_PROFILE" >> "$LOG"
else
    [ "$ASSET_PROFILE" != strict ] &&
    [ "$ASSET_STATUS" != copied_and_static_elf_checked ] ||
        fail 127 "WPE runtime reported installed assets but files are absent"
    unset WEBKIT_INJECTED_BUNDLE_PATH WEBKIT_INSPECTOR_RESOURCES_PATH
    printf 'wpe_installed_assets=legacy_absent\n' >> "$LOG"
fi
export WPE_PLATFORM=wayland
unset WPE_DISPLAY
if [ "$MODE" = --headless ]; then
    export WPE_PLATFORM=headless
    MODE=--smoke
fi
if [ "$WPE_PLATFORM" = wayland ] &&
   [ "$MODE" != --check-platform ] && [ "$MODE" != --check-library ] &&
   [ ! -S "${XDG_RUNTIME_DIR:-/nowhere}/${WAYLAND_DISPLAY:-invalid}" ]; then
    for dir in /var/run/0-runtime-dir /run/user/0 "/run/user/$(id -u 2>/dev/null || echo 1000)"; do
        for socket in wayland-1 wayland-0; do
            if [ -S "$dir/$socket" ]; then
                export XDG_RUNTIME_DIR="$dir" WAYLAND_DISPLAY="$socket"
                break 2
            fi
        done
    done
fi
# Fire4Nix runs under ROCKNIX Sway. On the verified Mali g29p1 userspace,
# EGL_DEFAULT_DISPLAY works when the driver's native display is Wayland.
# Preserve any explicitly configured driver selection.
if [ "$WPE_PLATFORM" = wayland ] && [ -z "${MALI_DEFAULT_DISPLAY+x}" ]; then
    export MALI_DEFAULT_DISPLAY=wayland
fi
printf 'platform=%s\nsocket=%s/%s\n' "$WPE_PLATFORM" \
    "${XDG_RUNTIME_DIR:-none}" "${WAYLAND_DISPLAY:-none}" >> "$LOG"
if [ "$WPE_PLATFORM" = wayland ] &&
   [ "$MODE" != --check-platform ] && [ "$MODE" != --check-library ] &&
   [ ! -S "${XDG_RUNTIME_DIR:-/nowhere}/${WAYLAND_DISPLAY:-invalid}" ]; then
    fail 69 "Wayland socket unavailable: start Fire4Nix from ROCKNIX Ports under Sway"
fi
export FIRE4NIX_LOW_MEMORY=${FIRE4NIX_LOW_MEMORY:-1}
# Keep website data, cookies and cache in a Fire4Nix-owned persistent profile
# on /storage. This survives replacement of the Ports folder and does not
# write into /usr or the firmware. Explicit XDG/FIRE4NIX overrides are kept.
PROFILE_ROOT=${FIRE4NIX_PROFILE_DIR:-}
if [ -z "$PROFILE_ROOT" ]; then
    if [ -d /storage ] && [ -w /storage ]; then
        PROFILE_ROOT=/storage/.config/Fire4Nix
    else
        PROFILE_ROOT="$ROOT/profile"
    fi
fi
if mkdir -p "$PROFILE_ROOT/data" "$PROFILE_ROOT/config" "$PROFILE_ROOT/cache" 2>/dev/null &&
   [ -w "$PROFILE_ROOT/data" ] && [ -w "$PROFILE_ROOT/cache" ]; then
    export XDG_DATA_HOME=${XDG_DATA_HOME:-$PROFILE_ROOT/data}
    export XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-$PROFILE_ROOT/config}
    export XDG_CACHE_HOME=${XDG_CACHE_HOME:-$PROFILE_ROOT/cache}
    printf 'profile_mode=persistent\\nprofile_root=%s\\n' "$PROFILE_ROOT" >> "$LOG"
else
    printf 'profile_mode=system_default_fallback\\nprofile_root_unavailable=%s\\n' "$PROFILE_ROOT" >> "$LOG"
fi
# RK3326 ROCKNIX provides GPU selection through its own profile.d.
# Recent ROCKNIX code migrates away from a global MALI_WAYLAND_AFBC=0.
# Do not impose this legacy tuning on the WebKit process; respect any
# explicit environment override provided by the user / GPU driver.
printf 'mali_wayland_afbc=%s\n' "${MALI_WAYLAND_AFBC:-not_overridden}" >> "$LOG"
printf 'mali_default_display=%s\n' "${MALI_DEFAULT_DISPLAY:-unconfigured}" >> "$LOG"
printf 'wsialloc_use_gbm=%s\n' "${WSIALLOC_USE_GBM:-unconfigured}" >> "$LOG"
export FIRE4NIX_HOME_URL="${FIRE4NIX_HOME_URL:-file://$ROOT/www/inicio.html}"
if [ "$MODE" = --verify-offline ]; then
    URL=${1:-file://$ROOT/www/primeiro-teste.html}
else
    URL=${1:-$FIRE4NIX_HOME_URL}
fi
start_gamepad
# Enable ELF loader tracing ONLY for an explicit offline preflight. Never
# enable it during interactive browsing: verbose paths can reveal local data.
if [ "${FIRE4NIX_LOADER_DEBUG:-0}" = 1 ] &&
   { [ "$MODE" = --check-library ] || [ "$MODE" = --check-platform ]; }; then
    ulimit -c 0 2>/dev/null || true
    LD_DEBUG=libs,versions,files
    LD_DEBUG_OUTPUT="$LOG_DIR/Fire4Nix-LD-$(date +%Y%m%d-%H%M%S)-$$"
    export LD_DEBUG LD_DEBUG_OUTPUT
    printf 'loader_debug=enabled\nloader_debug_prefix=%s\n' "$LD_DEBUG_OUTPUT" >> "$LOG"
else
    printf 'loader_debug=disabled\n' >> "$LOG"
fi
case "$MODE" in
  --check-library|--check-platform) "$BIN" "$MODE" >> "$LOG" 2>&1; code=$? ;;
  --smoke) "$BIN" --smoke "$URL" >> "$LOG" 2>&1; code=$? ;;
  --verify-offline) "$BIN" --verify-offline "$URL" >> "$LOG" 2>&1; code=$? ;;
  --open) "$BIN" "$URL" >> "$LOG" 2>&1; code=$? ;;
esac
exit "$code"
