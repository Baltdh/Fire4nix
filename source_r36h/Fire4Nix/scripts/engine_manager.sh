#!/bin/bash
set -euo pipefail

REAL_SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$0" 2>/dev/null || printf '%s\n' "$0")"
SCRIPT_DIR="$(cd "$(dirname "$REAL_SCRIPT_PATH")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$APP_DIR/scripts/fire4nix_env.sh"
fire4nix_bootstrap_environment "$APP_DIR"
fire4nix_log_reference_summary "$FIRE4NIX_REFERENCE_ROOT"

CONFIG_DIR="${FIRE4NIX_CONFIG_DIR:-$APP_DIR/.fire4nix}"
LOG_DIR="${FIRE4NIX_LOG_DIR:-$CONFIG_DIR/logs}"
LOG_FILE="${FIRE4NIX_LOG:-$LOG_DIR/fire4nix.log}"
RUNTIME_DIR="${FIRE4NIX_RUNTIME_DIR:-$APP_DIR/.fire4nix/runtime}"

mkdir -p "$CONFIG_DIR" "$LOG_DIR" "$RUNTIME_DIR" 2>/dev/null || true
chmod 700 "$RUNTIME_DIR" 2>/dev/null || true

export FIRE4NIX_CONFIG_DIR="$CONFIG_DIR"
export FIRE4NIX_CONF="${FIRE4NIX_CONF:-$CONFIG_DIR/fire4nix.conf}"
export FIRE4NIX_LOG="${FIRE4NIX_LOG:-$LOG_FILE}"
export FIRE4NIX_LOG_DIR="${FIRE4NIX_LOG_DIR:-$LOG_DIR}"
export FIRE4NIX_RUNTIME_DIR="${FIRE4NIX_RUNTIME_DIR:-$RUNTIME_DIR}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-$RUNTIME_DIR}"

audio_driver="$(fire4nix_choose_audio_driver)"
if [ -n "$audio_driver" ]; then
    export SDL_AUDIODRIVER="$audio_driver"
fi

mkdir -p "$CONFIG_DIR" 2>/dev/null || true
ENGINE_FILE="${FIRE4NIX_ENGINE_FILE:-$CONFIG_DIR/engine.conf}"
export FIRE4NIX_ENGINE_FILE="$ENGINE_FILE"
DEFAULT_ENGINE="${FIRE4NIX_DEFAULT_ENGINE:-auto}"
AUDIO_BACKEND="${FIRE4NIX_AUDIO_BACKEND:-auto}"

trim_value() {
    printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

usage() {
    cat <<'EOF'
Fire4Nix engine manager

Usage:
  engine_manager.sh get
  engine_manager.sh set <engine-name>
  engine_manager.sh use <engine-name>
  engine_manager.sh detect
  engine_manager.sh reset
  engine_manager.sh list
  engine_manager.sh status
  engine_manager.sh advance
EOF
}

current_engine()
{
    if [ -f "$ENGINE_FILE" ]; then
        value="$(fire4nix_read_trimmed_file "$ENGINE_FILE" || true)"
        value="$(trim_value "$value")"
        if [ -n "$value" ]; then
            if fire4nix_is_legacy_engine_label "$value"; then
                printf '%s' "auto"
                return 0
            fi
            printf '%s' "$value"
            return 0
        fi
    fi

    if [ -n "${FIRE4NIX_ENGINE:-}" ]; then
        value="$(trim_value "$FIRE4NIX_ENGINE")"
        if fire4nix_is_legacy_engine_label "$value"; then
            printf '%s' "auto"
            return 0
        fi
        printf '%s' "$value"
        return 0
    fi

    printf '%s' "$DEFAULT_ENGINE"
}

engine_source()
{
    if [ -f "$ENGINE_FILE" ] && [ -n "$(fire4nix_read_trimmed_file "$ENGINE_FILE" 2>/dev/null || true)" ]; then
        printf '%s' "file"
        return 0
    fi

    if [ -n "${FIRE4NIX_ENGINE:-}" ]; then
        printf '%s' "environment"
        return 0
    fi

    printf '%s' "default"
}

detect_engine() {
    fire4nix_detect_engine
}

current_version()
{
    version_file="$APP_DIR/src/fire4nix_version.hpp"
    if [ -f "$version_file" ]; then
        grep -E '^#define FIRE4NIX_VERSION ' "$version_file" 2>/dev/null | sed -E 's/^#define FIRE4NIX_VERSION "([^"]+)".*/\1/' | head -n 1
        return 0
    fi
    printf '%s' "unknown"
}

runtime_dir_state()
{
    if [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -d "${XDG_RUNTIME_DIR:-}" ] && [ -w "${XDG_RUNTIME_DIR:-}" ]; then
        printf '%s' "writable"
    elif [ -d "$CONFIG_DIR/runtime" ] && [ -w "$CONFIG_DIR/runtime" ]; then
        printf '%s' "fallback-writable"
    else
        printf '%s' "missing"
    fi
}

audio_group_state()
{
    if command -v id >/dev/null 2>&1 && id -nG 2>/dev/null | tr ' ' '\n' | grep -qx audio; then
        printf '%s' "audio"
    else
        printf '%s' "no-audio"
    fi
}

save_engine() {
    value="$(trim_value "$1")"
    if [ -z "$value" ]; then
        printf 'engine value cannot be empty\n' >&2
        exit 2
    fi
    printf '%s\n' "$value" > "$ENGINE_FILE"
    printf 'engine=%s\n' "$value"
}

case "${1:-get}" in
    get)
        current_engine
        printf '\n'
        ;;
    detect)
        detect_engine
        printf '\n'
        ;;
    set|use)
        shift || true
        if [ $# -eq 0 ]; then
            usage
            exit 2
        fi
        save_engine "$*"
        ;;
    reset)
        rm -f "$ENGINE_FILE"
        printf 'engine=%s\n' "auto"
        ;;
    list)
        cat <<EOF
auto
cog
wpe-launcher
wpe-browser
wpe-platform
wpe-native
wpe-native-launcher
wpe-platform-launcher
mini-browser
wpe-webkit-launcher
wpewebkit-launcher
chromium
chromium-browser
firefox-esr
firefox
surf
browser.arm64
EOF
        ;;
    status)
        printf 'version=%s\n' "$(current_version)"
        printf 'engine_file=%s\n' "$ENGINE_FILE"
        printf 'engine_source=%s\n' "$(engine_source)"
        printf 'current_engine=%s\n' "$(current_engine)"
        printf 'detected_engine=%s\n' "$(detect_engine)"
        printf 'audio_backend=%s\n' "$AUDIO_BACKEND"
        printf 'runtime_state=%s\n' "$(runtime_dir_state)"
        printf 'audio_group=%s\n' "$(audio_group_state)"
        printf 'reference_root=%s\n' "${FIRE4NIX_REFERENCE_ROOT:-bundled}"
        printf 'reference_summary=%s\n' "${FIRE4NIX_REFERENCE_SUMMARY:-bundled}"
        printf 'reference_features=%s\n' "${FIRE4NIX_REFERENCE_FEATURES:-bundled}"
        printf 'reference_manifest=%s\n' "${FIRE4NIX_REFERENCE_MANIFEST:-none}"
        printf 'reference_env=%s\n' "${FIRE4NIX_REFERENCE_ENV:-none}"
        printf 'reference_status=%s\n' "${FIRE4NIX_REFERENCE_STATUS:-none}"
        printf 'progress_stage=%s\n' "${FIRE4NIX_PROGRESS_STAGE:-marco3-start}"
        printf 'progress_stage_name=%s\n' "$(fire4nix_progress_stage_name)"
        printf 'progress_stage_summary=%s\n' "$(fire4nix_progress_stage_summary)"
        printf 'progress_focus=%s\n' "$(fire4nix_progress_focus)"
        printf 'progress_next_action=%s\n' "$(fire4nix_progress_next_action)"
        printf 'progress_acceptance=%s\n' "$(fire4nix_progress_acceptance)"
        printf 'bridge_journal_path=%s\n' "$(fire4nix_bridge_journal_path)"
        printf 'bridge_journal_count=%s\n' "$(fire4nix_bridge_journal_count)"
        printf 'bridge_journal_state=%s\n' "$(fire4nix_bridge_journal_state)"
        printf 'wpe_display=%s\n' "${WPE_DISPLAY:-${FIRE4NIX_WPE_DISPLAY:-auto}}"
        printf 'wpe_platform_binary=%s\n' "$(fire4nix_wpe_platform_binary)"
        printf 'cog_platform=%s\n' "${COG_PLATFORM_NAME:-${FIRE4NIX_COG_PLATFORM:-auto}}"
        printf 'cog_platform_params=%s\n' "${COG_PLATFORM_PARAMS:-${FIRE4NIX_COG_PLATFORM_PARAMS:-}}"
        printf 'fontconfig_file=%s\n' "${FONTCONFIG_FILE:-system}"
        printf 'ssl_cert_file=%s\n' "${SSL_CERT_FILE:-system}"
        printf 'xkb_config_root=%s\n' "${XKB_CONFIG_ROOT:-/usr/share/X11/xkb}"
        printf 'systemd_colors=%s\n' "${SYSTEMD_COLORS:-0}"
        printf 'config_dir=%s\n' "$CONFIG_DIR"
        printf 'runtime_dir=%s\n' "${XDG_RUNTIME_DIR:-$CONFIG_DIR/runtime}"
        printf 'session_type=%s\n' "${XDG_SESSION_TYPE:-unknown}"
        printf 'wayland_display=%s\n' "${WAYLAND_DISPLAY:-none}"
        printf 'moz_enable_wayland=%s\n' "${MOZ_ENABLE_WAYLAND:-1}"
        printf 'sdl_audiodriver=%s\n' "${SDL_AUDIODRIVER:-auto}"
        ;;
    advance)
        printf 'Fire4Nix advance snapshot\n'
        fire4nix_progress_snapshot
        printf 'progress_stage=%s\n' "$(fire4nix_progress_stage_label)"
        printf 'progress_stage_name=%s\n' "$(fire4nix_progress_stage_name)"
        printf 'progress_stage_summary=%s\n' "$(fire4nix_progress_stage_summary)"
        printf 'progress_focus=%s\n' "$(fire4nix_progress_focus)"
        printf 'progress_next_action=%s\n' "$(fire4nix_progress_next_action)"
        printf 'progress_acceptance=%s\n' "$(fire4nix_progress_acceptance)"
        printf 'bridge_journal_path=%s\n' "$(fire4nix_bridge_journal_path)"
        printf 'bridge_journal_count=%s\n' "$(fire4nix_bridge_journal_count)"
        printf 'bridge_journal_state=%s\n' "$(fire4nix_bridge_journal_state)"
        fire4nix_progress_plan | sed 's/^/plan: /'
        printf 'version=%s\n' "$(current_version)"
        printf 'engine=%s\n' "$(current_engine)"
        printf 'detected_engine=%s\n' "$(detect_engine)"
        printf 'selected_binary=%s\n' "$(fire4nix_engine_binary "$(current_engine)")"
        printf 'wpe_display=%s\n' "${WPE_DISPLAY:-${FIRE4NIX_WPE_DISPLAY:-auto}}"
        printf 'wpe_platform_binary=%s\n' "$(fire4nix_wpe_platform_binary)"
        printf 'cog_platform=%s\n' "${COG_PLATFORM_NAME:-${FIRE4NIX_COG_PLATFORM:-auto}}"
        ;;
    *)
        usage
        exit 2
        ;;
esac
