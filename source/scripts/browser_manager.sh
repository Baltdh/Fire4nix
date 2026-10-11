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

AUDIO_BACKEND="${FIRE4NIX_AUDIO_BACKEND:-auto}"
HOME_URL="${FIRE4NIX_HOME_URL:-$(fire4nix_default_home_url)}"
SEARCH_URL="${FIRE4NIX_SEARCH_URL:-https://duckduckgo.com/?q=%s}"
THEME_FILE="${FIRE4NIX_THEME_FILE:-$CONFIG_DIR/theme.conf}"
ENGINE_FILE="${FIRE4NIX_ENGINE_FILE:-$CONFIG_DIR/engine.conf}"

cleanup_stale_logs() {
    local log_dir="$LOG_DIR"
    local root_dir="$CONFIG_DIR"
    local retention_days="${FIRE4NIX_LOG_RETENTION_DAYS:-14}"
    find "$log_dir" -type f \( -name '*.log' -o -name '*.log.*' -o -name '*.bak' -o -name '*.old' -o -name '*.tmp' -o -name '*.trace' \) -mtime +"$retention_days" -delete 2>/dev/null || true
    find "$root_dir" -maxdepth 1 -type f \( -name '*.log' -o -name '*.log.*' -o -name '*.bak' -o -name '*.old' -o -name '*.tmp' -o -name '*.trace' \) -mtime +"$retention_days" -delete 2>/dev/null || true
}

cleanup_stale_logs

usage() {
    cat <<'EOF'
Fire4Nix browser manager

Usage:
  browser_manager.sh launch
  browser_manager.sh home
  browser_manager.sh open <url>
  browser_manager.sh search <query>
  browser_manager.sh status
  browser_manager.sh advance
  browser_manager.sh beta-check
  browser_manager.sh logs
EOF
}

log() {
    printf '[browser-manager] %s\n' "$*" >&2
}

urlencode_query() {
    python3 - "$1" <<'PY'
import sys, urllib.parse
print(urllib.parse.quote_plus(sys.argv[1]))
PY
}

trim_value() {
    printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

read_first_line() {
    path="$1"
    fire4nix_read_trimmed_file "$path" 2>/dev/null || true
}

current_value_from_file_or_env() {
    file="$1"
    env_name="$2"
    fallback="$3"
    value="$(trim_value "$(read_first_line "$file")")"
    if [ -n "$value" ]; then
        printf '%s' "$value"
        return 0
    fi
    if [ -n "${!env_name:-}" ]; then
        trim_value "${!env_name}"
        return 0
    fi
    printf '%s' "$fallback"
}

current_engine() {
    current_value_from_file_or_env "$ENGINE_FILE" FIRE4NIX_ENGINE "auto"
}

current_theme() {
    current_value_from_file_or_env "$THEME_FILE" FIRE4NIX_THEME "beta-dark"
}

theme_source() {
    if [ -f "$THEME_FILE" ]; then
        printf '%s' "file"
    elif [ -n "${FIRE4NIX_THEME:-}" ]; then
        printf '%s' "environment"
    else
        printf '%s' "default"
    fi
}

engine_source() {
    if [ -f "$ENGINE_FILE" ]; then
        printf '%s' "file"
    elif [ -n "${FIRE4NIX_ENGINE:-}" ]; then
        printf '%s' "environment"
    else
        printf '%s' "default"
    fi
}

current_version() {
    version_file="$APP_DIR/src/fire4nix_version.hpp"
    if [ -f "$version_file" ]; then
        grep -E '^#define FIRE4NIX_VERSION ' "$version_file" 2>/dev/null | sed -E 's/^#define FIRE4NIX_VERSION "([^"]+)".*/\1/' | head -n 1
        return 0
    fi
    printf '%s' "unknown"
}

runtime_dir_state() {
    if [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -d "${XDG_RUNTIME_DIR:-}" ] && [ -w "${XDG_RUNTIME_DIR:-}" ]; then
        printf '%s' "writable"
    elif [ -d "$RUNTIME_DIR" ] && [ -w "$RUNTIME_DIR" ]; then
        printf '%s' "fallback-writable"
    else
        printf '%s' "missing"
    fi
}

audio_group_state() {
    if command -v id >/dev/null 2>&1; then
        if id -nG 2>/dev/null | tr ' ' '\n' | grep -qx audio; then
            printf '%s' "audio"
        else
            printf '%s' "no-audio"
        fi
    else
        printf '%s' "unknown"
    fi
}

browser_binary_path() {
    local candidates=(
        "$APP_DIR/bin/fire4nix-wpe-platform"
        "$APP_DIR/bin/browser.arm64"
        "$APP_DIR/bin/browser"
        "$APP_DIR/build/browser.arm64"
        "$APP_DIR/build/browser"
        "$APP_DIR/browser.arm64"
        "$APP_DIR/browser"
        "$APP_DIR/fire4nix"
        "$(command -v browser 2>/dev/null || true)"
        "$(command -v fire4nix 2>/dev/null || true)"
    )
    local candidate
    for candidate in "${candidates[@]}"; do
        if [ -n "${candidate:-}" ] && [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    printf '%s\n' "missing"
}

report_check() {
    label="$1"
    path="$2"
    if [ -e "$path" ]; then
        printf 'ok   %-18s %s\n' "$label" "$path"
        return 0
    fi
    printf 'miss %-18s %s\n' "$label" "$path"
    return 1
}

set_start_page() {
    export FIRE4NIX_START_PAGE="$(fire4nix_normalize_target "$1")"
}

case "${1:-launch}" in
    launch)
        shift || true
        if [ $# -gt 0 ]; then
            set_start_page "$*"
        fi
        exec "$APP_DIR/scripts/run_browser.sh"
        ;;
    home)
        export FIRE4NIX_HOME_URL="$(fire4nix_default_home_url)"
        set_start_page "$HOME_URL"
        shift || true
        exec "$APP_DIR/scripts/run_browser.sh"
        ;;
    open)
        shift || true
        if [ $# -eq 0 ]; then
            log "missing url"
            usage
            exit 2
        fi
        set_start_page "$*"
        exec "$APP_DIR/scripts/run_browser.sh"
        ;;
    search)
        shift || true
        query="${*:-}"
        if [ -z "$query" ]; then
            log "missing search query"
            usage
            exit 2
        fi
        export FIRE4NIX_HOME_URL="$HOME_URL"
        export FIRE4NIX_SEARCH_URL="$SEARCH_URL"
        encoded_query="$(urlencode_query "$query")"
        set_start_page "$(printf '%s' "$SEARCH_URL" | sed "s/%s/$encoded_query/g")"
        exec "$APP_DIR/scripts/run_browser.sh"
        ;;
    status)
        printf 'app_dir=%s\n' "$APP_DIR"
        printf 'home_url=%s\n' "$HOME_URL"
        printf 'search_url=%s\n' "$SEARCH_URL"
        printf 'theme_file=%s\n' "$THEME_FILE"
        printf 'engine_file=%s\n' "$ENGINE_FILE"
        printf 'log_file=%s\n' "$LOG_FILE"
        printf 'log_dir=%s\n' "$LOG_DIR"
        printf 'runtime_dir=%s\n' "$RUNTIME_DIR"
        printf 'xdg_runtime_dir=%s\n' "${XDG_RUNTIME_DIR:-$RUNTIME_DIR}"
        printf 'session_type=%s\n' "${XDG_SESSION_TYPE:-unknown}"
        printf 'wayland_display=%s\n' "${WAYLAND_DISPLAY:-none}"
        printf 'moz_enable_wayland=%s\n' "${MOZ_ENABLE_WAYLAND:-1}"
        printf 'sdl_videodriver=%s\n' "${SDL_VIDEODRIVER:-auto}"
        printf 'sdl_audiodriver=%s\n' "${SDL_AUDIODRIVER:-auto}"
        printf 'audio_backend=%s\n' "$AUDIO_BACKEND"
        printf 'runtime_state=%s\n' "$(runtime_dir_state)"
        printf 'audio_group=%s\n' "$(audio_group_state)"
        printf 'wpe_platform_binary=%s\n' "$(fire4nix_wpe_platform_binary)"
        printf 'reference_root=%s\n' "${FIRE4NIX_REFERENCE_ROOT:-bundled}"
        printf 'reference_summary=%s\n' "${FIRE4NIX_REFERENCE_SUMMARY:-bundled}"
        printf 'reference_features=%s\n' "${FIRE4NIX_REFERENCE_FEATURES:-bundled}"
        printf 'reference_manifest=%s\n' "${FIRE4NIX_REFERENCE_MANIFEST:-none}"
        printf 'reference_env=%s\n' "${FIRE4NIX_REFERENCE_ENV:-none}"
        printf 'reference_status=%s\n' "${FIRE4NIX_REFERENCE_STATUS:-none}"
        printf 'wpe_display=%s\n' "${WPE_DISPLAY:-${FIRE4NIX_WPE_DISPLAY:-auto}}"
        printf 'wpe_platform_binary=%s\n' "${FIRE4NIX_WPE_PLATFORM_BINARY:-none}"
        printf 'engine_selected=%s\n' "${FIRE4NIX_ENGINE_SELECTED:-$(current_engine)}"
        printf 'engine_profile_dir=%s\n' "${FIRE4NIX_ENGINE_PROFILE_DIR:-${CONFIG_DIR}/profiles/default}"
        printf 'cog_platform=%s\n' "${COG_PLATFORM_NAME:-${FIRE4NIX_COG_PLATFORM:-auto}}"
        printf 'cog_platform_params=%s\n' "${COG_PLATFORM_PARAMS:-${FIRE4NIX_COG_PLATFORM_PARAMS:-}}"
        printf 'fontconfig_file=%s\n' "${FONTCONFIG_FILE:-system}"
        printf 'ssl_cert_file=%s\n' "${SSL_CERT_FILE:-system}"
        printf 'xkb_config_root=%s\n' "${XKB_CONFIG_ROOT:-/usr/share/X11/xkb}"
        printf 'systemd_colors=%s\n' "${SYSTEMD_COLORS:-0}"
        printf 'start_page=%s\n' "${FIRE4NIX_START_PAGE:-$HOME_URL}"
        printf 'version=%s\n' "$(current_version)"
        printf 'browser_mode=%s\n' "${FIRE4NIX_BROWSER_MODE:-beta}"
        printf 'progress_stage=%s\n' "${FIRE4NIX_PROGRESS_STAGE:-marco3-start}"
        printf 'progress_stage_name=%s\n' "$(fire4nix_progress_stage_name)"
        printf 'progress_stage_summary=%s\n' "$(fire4nix_progress_stage_summary)"
        printf 'progress_focus=%s\n' "$(fire4nix_progress_focus)"
        printf 'progress_next_action=%s\n' "$(fire4nix_progress_next_action)"
        printf 'progress_acceptance=%s\n' "$(fire4nix_progress_acceptance)"
        printf 'bridge_journal_path=%s\n' "$(fire4nix_bridge_journal_path)"
        printf 'bridge_journal_count=%s\n' "$(fire4nix_bridge_journal_count)"
        printf 'bridge_journal_state=%s\n' "$(fire4nix_bridge_journal_state)"
        printf 'ui_profile=%s\n' "${FIRE4NIX_UI_PROFILE:-compact}"
        printf 'theme=%s\n' "$(current_theme)"
        printf 'theme_source=%s\n' "$(theme_source)"
        printf 'engine=%s\n' "$(current_engine)"
        printf 'engine_selected=%s\n' "${FIRE4NIX_ENGINE_SELECTED:-$(current_engine)}"
        printf 'engine_profile_dir=%s\n' "${FIRE4NIX_ENGINE_PROFILE_DIR:-${CONFIG_DIR}/profiles/default}"
        printf 'engine_source=%s\n' "$(engine_source)"
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
        printf 'current_engine=%s\n' "$(current_engine)"
        printf 'detected_engine=%s\n' "$(fire4nix_detect_engine)"
        printf 'selected_binary=%s\n' "$(fire4nix_engine_binary "$(current_engine)")"
        printf 'wpe_display=%s\n' "${WPE_DISPLAY:-${FIRE4NIX_WPE_DISPLAY:-auto}}"
        printf 'reference_status=%s\n' "${FIRE4NIX_REFERENCE_STATUS:-none}"
        ;;
    beta-check)
        fail=0
        printf 'Fire4Nix beta check\n'
        printf 'app_dir=%s\n' "$APP_DIR"
        printf 'platform=%s\n' "${FIRE4NIX_PLATFORM:-ROCKNIX}"
        printf 'home_url=%s\n' "${FIRE4NIX_HOME_URL:-$(fire4nix_default_home_url)}"
        printf 'start_page=%s\n' "${FIRE4NIX_START_PAGE:-${FIRE4NIX_HOME_URL:-$(fire4nix_default_home_url)}}"
        printf 'search_url=%s\n' "${FIRE4NIX_SEARCH_URL:-https://duckduckgo.com/?q=%s}"
        printf 'session_label=%s\n' "${FIRE4NIX_SESSION_LABEL:-Fire4Nix ROCKNIX beta Marco 3 start}"
        printf 'version=%s\n' "$(current_version)"
        printf 'browser_mode=%s\n' "${FIRE4NIX_BROWSER_MODE:-beta}"
        printf 'progress_stage=%s\n' "${FIRE4NIX_PROGRESS_STAGE:-marco3-start}"
        printf 'progress_stage_name=%s\n' "$(fire4nix_progress_stage_name)"
        printf 'progress_stage_summary=%s\n' "$(fire4nix_progress_stage_summary)"
        printf 'progress_focus=%s\n' "$(fire4nix_progress_focus)"
        printf 'progress_next_action=%s\n' "$(fire4nix_progress_next_action)"
        printf 'progress_acceptance=%s\n' "$(fire4nix_progress_acceptance)"
        printf 'bridge_journal_path=%s\n' "$(fire4nix_bridge_journal_path)"
        printf 'bridge_journal_count=%s\n' "$(fire4nix_bridge_journal_count)"
        printf 'bridge_journal_state=%s\n' "$(fire4nix_bridge_journal_state)"
        printf 'ui_profile=%s\n' "${FIRE4NIX_UI_PROFILE:-compact}"
        printf 'theme=%s\n' "$(current_theme)"
        printf 'theme_source=%s\n' "$(theme_source)"
        printf 'engine=%s\n' "$(current_engine)"
        printf 'engine_selected=%s\n' "${FIRE4NIX_ENGINE_SELECTED:-$(current_engine)}"
        printf 'engine_profile_dir=%s\n' "${FIRE4NIX_ENGINE_PROFILE_DIR:-${CONFIG_DIR}/profiles/default}"
        printf 'engine_source=%s\n' "$(engine_source)"
        printf 'theme_file=%s\n' "$THEME_FILE"
        printf 'engine_file=%s\n' "$ENGINE_FILE"
        printf 'log_file=%s\n' "$LOG_FILE"
        printf 'log_dir=%s\n' "$LOG_DIR"
        printf 'config_root=%s\n' "$CONFIG_DIR"
        printf 'runtime_dir=%s\n' "$RUNTIME_DIR"
        printf 'xdg_runtime_dir=%s\n' "${XDG_RUNTIME_DIR:-$RUNTIME_DIR}"
        printf 'session_type=%s\n' "${XDG_SESSION_TYPE:-unknown}"
        printf 'wayland_display=%s\n' "${WAYLAND_DISPLAY:-none}"
        printf 'moz_enable_wayland=%s\n' "${MOZ_ENABLE_WAYLAND:-1}"
        printf 'sdl_videodriver=%s\n' "${SDL_VIDEODRIVER:-auto}"
        printf 'sdl_audiodriver=%s\n' "${SDL_AUDIODRIVER:-auto}"
        printf 'audio_backend=%s\n' "$AUDIO_BACKEND"
        printf 'runtime_state=%s\n' "$(runtime_dir_state)"
        printf 'audio_group=%s\n' "$(audio_group_state)"
        printf 'wpe_platform_binary=%s\n' "$(fire4nix_wpe_platform_binary)"
        if [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -d "$XDG_RUNTIME_DIR" ] && [ -w "$XDG_RUNTIME_DIR" ]; then
            printf 'ok   %-18s %s\n' "runtime dir" "$XDG_RUNTIME_DIR"
        elif [ -d "$RUNTIME_DIR" ] && [ -w "$RUNTIME_DIR" ]; then
            printf 'ok   %-18s %s\n' "runtime dir" "$RUNTIME_DIR"
        else
            printf 'miss %-18s %s\n' "runtime dir" "$RUNTIME_DIR"
            fail=1
        fi
        browser_exec="$(browser_binary_path)"
        if [ "$browser_exec" != "missing" ]; then
            printf 'ok   %-18s %s\n' "browser exec" "$browser_exec"
        else
            printf 'miss %-18s %s\n' "browser exec" "$APP_DIR/bin/browser.arm64"
            fail=1
        fi
        selected_binary="missing"
        if [ -n "${FIRE4NIX_ENGINE:-}" ]; then
            selected_binary="$(fire4nix_engine_binary "${FIRE4NIX_ENGINE:-}")"
        fi
        if [ -z "$selected_binary" ] || [ "$selected_binary" = "missing" ]; then
            selected_binary="$browser_exec"
            if [ "$selected_binary" = "missing" ]; then
                if [ -x "$APP_DIR/fire4nix" ]; then
                    selected_binary="$APP_DIR/fire4nix"
                fi
            fi
        fi
        printf 'selected_binary=%s\n' "$selected_binary"
        printf 'wpe_platform_binary=%s\n' "$(fire4nix_wpe_platform_binary)"
        printf 'theme_source=%s\n' "$(theme_source)"
        printf 'engine_source=%s\n' "$(engine_source)"
        report_check "launcher" "$APP_DIR/scripts/run_browser.sh" || fail=1
        report_check "browser" "$browser_exec" || fail=1
        report_check "fire4nix" "$APP_DIR/fire4nix" || fail=1
        report_check "browser src" "$APP_DIR/src/gui/browser_chrome.cpp" || fail=1
        report_check "main src" "$APP_DIR/src/main.cpp" || fail=1
        report_check "version" "$APP_DIR/src/fire4nix_version.hpp" || fail=1
        report_check "config" "$APP_DIR/fire4nix.conf" || true
        report_check "theme script" "$APP_DIR/scripts/theme_manager.sh" || fail=1
        report_check "engine script" "$APP_DIR/scripts/engine_manager.sh" || fail=1
        report_check "theme config" "$THEME_FILE" || true
        report_check "engine config" "$ENGINE_FILE" || true
        if [ -w "$CONFIG_DIR" ] 2>/dev/null; then
            printf 'ok   %-18s %s\n' "config dir" "$CONFIG_DIR"
        else
            printf 'miss %-18s %s\n' "config dir" "$CONFIG_DIR"
            fail=1
        fi
        if [ -d "$APP_DIR/theme" ]; then
            printf 'ok   %-18s %s\n' "theme dir" "$APP_DIR/theme"
        else
            printf 'miss %-18s %s\n' "theme dir" "$APP_DIR/theme"
            fail=1
        fi
        if [ -d "$APP_DIR/src/gui" ]; then
            printf 'ok   %-18s %s\n' "gui src" "$APP_DIR/src/gui"
        else
            printf 'miss %-18s %s\n' "gui src" "$APP_DIR/src/gui"
            fail=1
        fi
        if [ "$fail" -eq 0 ]; then
            printf 'beta_status=ready\n'
        else
            printf 'beta_status=needs_attention\n'
        fi
        exit "$fail"
        ;;
    logs)
        if [ -f "$LOG_FILE" ]; then
            tail -n 120 "$LOG_FILE"
        else
            log "log file not found: $LOG_FILE"
            exit 1
        fi
        ;;
    *)
        usage
        exit 2
        ;;
esac
