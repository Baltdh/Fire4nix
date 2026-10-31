#!/bin/sh
# Fire4Nix 1.02: launch from ROCKNIX Ports regardless of the shell's cwd.
# No firmware edits, network installer, runtime replacement or sandbox bypass.
set -u
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 2
umask 077
if [ -d /storage ] && [ -w /storage ]; then
    LOG=/storage/Fire4Nix-PORTS-ultimo.txt
elif [ -w "$HERE" ]; then
    LOG="$HERE/Fire4Nix-PORTS-ultimo.txt"
else
    LOG="${TMPDIR:-/tmp}/Fire4Nix-PORTS-ultimo.txt"
fi
: > "$LOG" || exit 73
log() { printf '%s\n' "$*" >> "$LOG"; }
# Ports can keep the native launcher on one SD and the large WPE runtime on
# another. Only accept a real ELF64 little-endian AArch64 library.
is_elf64_aarch64() {
    file_path=$1
    [ -f "$file_path" ] && [ -r "$file_path" ] && [ ! -L "$file_path" ] || return 1
    command -v od >/dev/null 2>&1 || return 1
    elf_bytes=$(od -An -v -t x1 -N20 "$file_path" 2>/dev/null | tr '\n' ' ') || return 1
    set -- $elf_bytes
    [ "$#" -ge 20 ] || return 1
    [ "$1" = 7f ] && [ "$2" = 45 ] && [ "$3" = 4c ] && [ "$4" = 46 ] &&
    [ "$5" = 02 ] && [ "$6" = 01 ] && [ "${19}" = b7 ] && [ "${20}" = 00 ]
}
if [ ! -S "${XDG_RUNTIME_DIR:-/nonexistent}/${WAYLAND_DISPLAY:-wayland-0}" ] &&
   [ ! -S "${XDG_RUNTIME_DIR:-/nonexistent}/wayland-1" ]; then
    for session_dir in /var/run/0-runtime-dir /run/user/0 "/run/user/$(id -u)"; do
        for display_name in "${WAYLAND_DISPLAY:-wayland-1}" wayland-1 wayland-0; do
            if [ -S "$session_dir/$display_name" ]; then
                XDG_RUNTIME_DIR=$session_dir
                WAYLAND_DISPLAY=$display_name
                export XDG_RUNTIME_DIR WAYLAND_DISPLAY
                break 2
            fi
        done
    done
elif [ ! -S "${XDG_RUNTIME_DIR:-/nonexistent}/${WAYLAND_DISPLAY:-wayland-0}" ] &&
     [ -S "${XDG_RUNTIME_DIR:-/nonexistent}/wayland-1" ]; then
    WAYLAND_DISPLAY=wayland-1
    export WAYLAND_DISPLAY
fi
log "fire4nix_portable_launcher=1.03"
log "launcher=$0"
log "wayland=${XDG_RUNTIME_DIR:-missing}/${WAYLAND_DISPLAY:-missing}"
status=127
selected=""
for root in "${FIRE4NIX_ROOT:-}" "$HERE/fire4nix-completo" "$HERE/Fire4Nix" "$HERE" \
    /storage/games-internal/roms/ports/fire4nix-completo \
    /storage/games-external/roms/ports/fire4nix-completo \
    /storage/roms/ports/fire4nix-completo \
    /storage/games-internal/roms/tools/Fire4Nix \
    /storage/games-external/roms/tools/Fire4Nix \
    /storage/roms/tools/Fire4Nix; do
    [ -n "$root" ] && [ -d "$root" ] || continue
    if [ -f "$root/Fire4Nix-Iniciar.sh" ] &&
       [ -s "$root/bin/fire4nix-native-aarch64" ]; then
        runtime_root=""
        invalid_runtime=""
        if [ -n "${FIRE4NIX_RUNTIME_ROOT:-}" ]; then
            candidate=$FIRE4NIX_RUNTIME_ROOT
            case "$candidate" in
                /*) ;;
                *) candidate="$root/$candidate" ;;
            esac
            if [ -s "$candidate/lib/libWPEWebKit-2.0.so.1" ]; then
                if is_elf64_aarch64 "$candidate/lib/libWPEWebKit-2.0.so.1"; then
                    runtime_root=$candidate
                else
                    invalid_runtime=$candidate
                fi
            fi
        else
            for candidate in "$root/runtime" \
                "${FIRE4NIX_ROMS:-/no-roms}/tools/Fire4Nix/runtime" \
                "${FIRE4NIX_ROMS:-/no-roms}/ports/fire4nix-completo/runtime" \
                /storage/games-internal/roms/tools/Fire4Nix/runtime \
                /storage/games-external/roms/tools/Fire4Nix/runtime \
                /storage/roms/tools/Fire4Nix/runtime \
                /storage/games-internal/roms/ports/fire4nix-completo/runtime \
                /storage/games-external/roms/ports/fire4nix-completo/runtime \
                /storage/roms/ports/fire4nix-completo/runtime; do
                if [ -s "$candidate/lib/libWPEWebKit-2.0.so.1" ]; then
                    if is_elf64_aarch64 "$candidate/lib/libWPEWebKit-2.0.so.1"; then
                        runtime_root=$candidate
                        break
                    elif [ -z "$invalid_runtime" ]; then
                        invalid_runtime=$candidate
                    fi
                fi
            done
        fi
        if [ -z "$runtime_root" ]; then
            [ -n "$invalid_runtime" ] && log "skipped_invalid_runtime_elf=$invalid_runtime"
            log "skipped_no_valid_wpe_runtime=$root"
            continue
        fi
        # Match the primary launcher: only a verified ROCKNIX Wayland
        # GPU-off report permits omitting WPEGPUProcess. No report retains
        # the conservative three-process requirement for legacy runtimes.
        gpu_required=1
        gpu_report="$runtime_root/BUILD-REPORT.txt"
        if [ -e "$gpu_report" ] || [ -L "$gpu_report" ]; then
            if [ ! -f "$gpu_report" ] || [ -L "$gpu_report" ]; then
                log "skipped_invalid_gpu_report=$runtime_root"
                continue
            fi
            gpu_profile=$(sed -n 's/^GPU_PROCESS_PROFILE=//p' "$gpu_report") || {
                log "skipped_unreadable_gpu_report=$runtime_root"
                continue
            }
            case "$gpu_profile" in
                disabled_verified_wayland) gpu_required=0 ;;
                required_unverified|enabled_verified|'') gpu_required=1 ;;
                *) log "skipped_invalid_gpu_profile=$runtime_root"; continue ;;
            esac
        fi
        missing_child=""
        for child in WPEWebProcess WPENetworkProcess; do
            child_path="$runtime_root/libexec/wpe-webkit-2.0/$child"
            if ! is_elf64_aarch64 "$child_path"; then
                missing_child="$missing_child $child"
            fi
        done
        if [ "$gpu_required" -eq 1 ] &&
           ! is_elf64_aarch64 "$runtime_root/libexec/wpe-webkit-2.0/WPEGPUProcess"; then
            missing_child="$missing_child WPEGPUProcess"
        fi
        if [ -n "$missing_child" ]; then
            log "skipped_incomplete_or_invalid_runtime=$runtime_root missing=$missing_child"
            continue
        fi
        selected=$root
        log "selected_install=$selected"
        log "selected_runtime=$runtime_root"
        log 'launch_mode=native-wpeplatform'
        FIRE4NIX_RUNTIME_ROOT="$runtime_root" \
        FIRE4NIX_LOG_DIR="${FIRE4NIX_LOG_DIR:-$(dirname "$LOG")}" \
          sh "$root/Fire4Nix-Iniciar.sh" --open "$@" >> "$LOG" 2>&1
        status=$?
        break
    fi
    if [ -f "$root/scripts/run_browser.sh" ] &&
       [ -f "$root/scripts/fire4nix_env.sh" ] &&
       [ -z "${legacy_root:-}" ]; then
        legacy_root=$root
    fi
done
if [ -z "$selected" ] && [ -n "${legacy_root:-}" ]; then
    selected=$legacy_root
    log "selected_legacy=$selected"
    if command -v bash >/dev/null 2>&1; then
        log 'launch_mode=legacy-bash'
        bash "$selected/scripts/run_browser.sh" "$@" >> "$LOG" 2>&1
        status=$?
    else
        log 'error=bash_unavailable_for_legacy_engine'
    fi
fi
if [ -z "$selected" ]; then
    log 'error=no_complete_fire4nix_install_found'
    log 'hint=Copy full Fire4Nix package beside this script, or install in roms/ports/fire4nix-completo'
fi
log "real_browser_exit=$status"
case "$status" in
  139) log 'diagnosis=SIGSEGV_in_native_runtime_not_a_Ports_script_problem' ;;
  127) log 'diagnosis=missing_binary_or_webkit_dependency_consult_full_log' ;;
  78) log 'diagnosis=WPEPlatform_API_absent_in_webkit_runtime' ;;
esac
tail -n 20 "$LOG" 2>/dev/null || true
exit "$status"
