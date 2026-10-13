#!/bin/bash
# Fire4Nix launcher for ROCKNIX / Wayland / Sway devices.

set -euo pipefail

REAL_SCRIPT_PATH=$(readlink -f "$0" 2>/dev/null || python3 -c "import os, sys; print(os.path.realpath(sys.argv[1]))" "$0" 2>/dev/null || echo "$0")
SCRIPT_DIR="$(cd "$(dirname "$REAL_SCRIPT_PATH")" && pwd)"
if [[ "$SCRIPT_DIR" == */scripts ]]; then
    APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
else
    APP_DIR="$SCRIPT_DIR"
fi
source "$APP_DIR/scripts/fire4nix_env.sh"
fire4nix_bootstrap_environment "$APP_DIR"
fire4nix_log_reference_summary "$FIRE4NIX_REFERENCE_ROOT"

CONFIG_DIR="${FIRE4NIX_CONFIG_DIR:-$APP_DIR/.fire4nix}"
LOG_DIR="${FIRE4NIX_LOG_DIR:-$CONFIG_DIR/logs}"
RUNTIME_DIR="${FIRE4NIX_RUNTIME_DIR:-$APP_DIR/.fire4nix/runtime}"

mkdir -p "$CONFIG_DIR/cache" "$LOG_DIR" "$RUNTIME_DIR" 2>/dev/null || true
chmod 700 "$RUNTIME_DIR" 2>/dev/null || true

export FIRE4NIX_CONFIG_DIR="$CONFIG_DIR"
export FIRE4NIX_CONF="${FIRE4NIX_CONF:-$CONFIG_DIR/fire4nix.conf}"
export FIRE4NIX_CACHE_DIR="${FIRE4NIX_CACHE_DIR:-$CONFIG_DIR/cache}"
export FIRE4NIX_LOG_DIR="${FIRE4NIX_LOG_DIR:-$LOG_DIR}"
export FIRE4NIX_RUNTIME_DIR="${FIRE4NIX_RUNTIME_DIR:-$RUNTIME_DIR}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-$RUNTIME_DIR}"
export FIRE4NIX_LOG="${FIRE4NIX_LOG:-$LOG_DIR/fire4nix.log}"
export FIRE4NIX_HOME_URL="${FIRE4NIX_HOME_URL:-about:home}"
export FIRE4NIX_SEARCH_URL="${FIRE4NIX_SEARCH_URL:-https://duckduckgo.com/?q=%s}"
export FIRE4NIX_SESSION_LABEL="${FIRE4NIX_SESSION_LABEL:-Fire4Nix ROCKNIX beta Marco 3 start}"
export FIRE4NIX_VERSION="${FIRE4NIX_VERSION:-0.83-beta-rocknix-marco3-start}"
export FIRE4NIX_BETA="${FIRE4NIX_BETA:-1}"
export FIRE4NIX_BROWSER_MODE="${FIRE4NIX_BROWSER_MODE:-beta}"
export FIRE4NIX_UI_PROFILE="${FIRE4NIX_UI_PROFILE:-compact}"
export FIRE4NIX_ENGINE="${FIRE4NIX_ENGINE:-auto}"
export FIRE4NIX_STARTUP_HINT="${FIRE4NIX_STARTUP_HINT:-rocknix-marco3-start}"
export FIRE4NIX_BETA_READY="${FIRE4NIX_BETA_READY:-1}"
export FIRE4NIX_THEME_FILE="${FIRE4NIX_THEME_FILE:-$CONFIG_DIR/theme.conf}"
export FIRE4NIX_ENGINE_FILE="${FIRE4NIX_ENGINE_FILE:-$CONFIG_DIR/engine.conf}"
export FIRE4NIX_START_PAGE="${FIRE4NIX_START_PAGE:-${FIRE4NIX_HOME_URL}}"
export FIRE4NIX_BROWSER_BINARY="${FIRE4NIX_BROWSER_BINARY:-}"
export FIRE4NIX_AUDIO_BACKEND="${FIRE4NIX_AUDIO_BACKEND:-auto}"
export FIRE4NIX_PROGRESS_STAGE="${FIRE4NIX_PROGRESS_STAGE:-marco3-start}"
export FIRE4NIX_BROWSER_BRIDGE="${FIRE4NIX_BROWSER_BRIDGE:-bridge-marco3-start}"
export FIRE4NIX_BRIDGE_JOURNAL="${FIRE4NIX_BRIDGE_JOURNAL:-$RUNTIME_DIR/bridge-journal.log}"
export FIRE4NIX_ENGINE_PRIORITY="${FIRE4NIX_ENGINE_PRIORITY:-wpe-platform,cog,chromium,firefox,browser.arm64}"

export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export MOZ_ENABLE_WAYLAND="${MOZ_ENABLE_WAYLAND:-1}"
export GDK_BACKEND="${GDK_BACKEND:-wayland}"
export SDL_VIDEODRIVER="${SDL_VIDEODRIVER:-wayland}"
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-wayland}"

audio_driver="$(fire4nix_choose_audio_driver)"
if [ -n "$audio_driver" ]; then
    export SDL_AUDIODRIVER="$audio_driver"
fi

cleanup_stale_logs() {
    local log_dir="${FIRE4NIX_LOG_DIR:-$FIRE4NIX_CONFIG_DIR/logs}"
    local root_dir="${FIRE4NIX_CONFIG_DIR:-$APP_DIR/.fire4nix}"
    local retention_days="${FIRE4NIX_LOG_RETENTION_DAYS:-14}"
    [ -d "$log_dir" ] || return 0
    find "$log_dir" -type f \( -name '*.log' -o -name '*.log.*' -o -name '*.bak' -o -name '*.old' -o -name '*.tmp' -o -name '*.trace' -o -name '*.1' -o -name '*.2' \) -mtime +"$retention_days" -delete 2>/dev/null || true
    find "$root_dir" -maxdepth 1 -type f \( -name '*.log' -o -name '*.log.*' -o -name '*.bak' -o -name '*.old' -o -name '*.tmp' -o -name '*.trace' -o -name '*.1' -o -name '*.2' \) -mtime +"$retention_days" -delete 2>/dev/null || true
}
cleanup_stale_logs

write_startup_snapshot() {
    local snapshot="$FIRE4NIX_LOG_DIR/startup.snapshot"
    {
        echo "version=${FIRE4NIX_VERSION}"
        echo "session=${FIRE4NIX_SESSION_LABEL}"
        echo "platform=${FIRE4NIX_PLATFORM}"
        echo "session_type=${XDG_SESSION_TYPE:-unknown}"
        echo "wayland_display=${WAYLAND_DISPLAY:-none}"
        echo "xdg_runtime_dir=${XDG_RUNTIME_DIR:-$FIRE4NIX_RUNTIME_DIR}"
        echo "sdl_videodriver=${SDL_VIDEODRIVER:-auto}"
        echo "sdl_audiodriver=${SDL_AUDIODRIVER:-auto}"
        echo "moz_enable_wayland=${MOZ_ENABLE_WAYLAND:-1}"
        echo "runtime_writable=$(if [ -w "${XDG_RUNTIME_DIR:-$FIRE4NIX_RUNTIME_DIR}" ]; then echo yes; else echo no; fi)"
        echo "audio_group=$(id -nG 2>/dev/null | tr ' ' ',' | grep -o 'audio' || true)"
        echo "reference_root=${FIRE4NIX_REFERENCE_ROOT:-bundled}"
        echo "reference_summary=${FIRE4NIX_REFERENCE_SUMMARY:-bundled}"
        echo "reference_status=${FIRE4NIX_REFERENCE_STATUS:-none}"
        echo "reference_manifest=${FIRE4NIX_REFERENCE_MANIFEST:-none}"
        echo "reference_env=${FIRE4NIX_REFERENCE_ENV:-none}"
        echo "fontconfig_file=${FONTCONFIG_FILE:-system}"
        echo "ssl_cert_file=${SSL_CERT_FILE:-system}"
        echo "xkb_config_root=${XKB_CONFIG_ROOT:-/usr/share/X11/xkb}"
        echo "systemd_colors=${SYSTEMD_COLORS:-0}"
        echo "progress_stage=${FIRE4NIX_PROGRESS_STAGE:-marco3-start}"
        echo "bridge_journal=${FIRE4NIX_BRIDGE_JOURNAL:-$RUNTIME_DIR/bridge-journal.log}"
        echo "bridge_journal_path=${FIRE4NIX_BRIDGE_JOURNAL_PATH:-${FIRE4NIX_BRIDGE_JOURNAL:-$RUNTIME_DIR/bridge-journal.log}}"
        echo "bridge_journal_count=${FIRE4NIX_BRIDGE_JOURNAL_COUNT:-0}"
        echo "bridge_journal_state=${FIRE4NIX_BRIDGE_JOURNAL_STATE:-none}"
    } > "$snapshot" 2>/dev/null || true
}

write_startup_snapshot

if [ -f "$APP_DIR/fire4nix.conf" ] && [ ! -f "$FIRE4NIX_CONFIG_DIR/fire4nix.conf" ]; then
    cp -f "$APP_DIR/fire4nix.conf" "$FIRE4NIX_CONFIG_DIR/fire4nix.conf" 2>/dev/null || true
fi

is_wrapper_candidate() {
    local candidate="${1:-}"
    case "$candidate" in
        "" )
            return 0
            ;;
        "$APP_DIR/scripts/run_browser.sh")
            return 0
            ;;
        */fire4nix|*/fire4nix.sh|*/Fire4Nix|*/run_browser.sh|*/browser_manager.sh|*/engine_manager.sh|*/theme_manager.sh)
            return 0
            ;;
    esac
    return 1
}

ensure_local_binary_exec() {
    local local_binary="$APP_DIR/bin/browser.arm64"
    local wpe_wrapper="$APP_DIR/bin/fire4nix-wpe-platform"
    if [[ -f "$local_binary" && ! -x "$local_binary" ]]; then
        chmod +x "$local_binary" 2>/dev/null || true
    fi
    if [[ -f "$wpe_wrapper" && ! -x "$wpe_wrapper" ]]; then
        chmod +x "$wpe_wrapper" 2>/dev/null || true
    fi
}

find_browser_binary() {
    local candidates=(
        "${FIRE4NIX_BINARY:-}"
        "$APP_DIR/bin/browser.arm64"
        "$APP_DIR/bin/fire4nix-wpe-platform"
        "$APP_DIR/bin/browser"
        "$APP_DIR/build/browser.arm64"
        "$APP_DIR/build/browser"
        "$APP_DIR/browser.arm64"
        "$APP_DIR/browser"
        "$(command -v browser 2>/dev/null || true)"
        "$(command -v fire4nix 2>/dev/null || true)"
    )
    local candidate
    ensure_local_binary_exec
    for candidate in "${candidates[@]}"; do
        if [[ -n "${candidate:-}" && -x "$candidate" ]] && ! is_wrapper_candidate "$candidate"; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    printf '%s\n' "$APP_DIR/bin/browser.arm64"
}

FIRE4NIX_BINARY="$(find_browser_binary)"
export FIRE4NIX_BINARY

read_config_value() {
    local file="$1"
    local env_name="$2"
    local default_value="$3"
    local value
    local source

    if [ -f "$file" ]; then
        value="$(fire4nix_read_trimmed_file "$file" 2>/dev/null || true)"
        if [ -n "${value:-}" ]; then
            printf '%s\n' "$value"
            printf '%s\n' "file"
            return 0
        fi
    fi

    if [ -n "${!env_name:-}" ]; then
        printf '%s\n' "${!env_name}"
        printf '%s\n' "environment"
        return 0
    fi

    printf '%s\n' "$default_value"
    printf '%s\n' "default"
}

ensure_default_config_file() {
    local file="$1"
    local value="$2"
    if [ ! -f "$file" ]; then
        printf '%s\n' "$value" > "$file" 2>/dev/null || true
    fi
}

# Prefer persisted config; create a first-run default when no config exists.
if [ -f "$FIRE4NIX_THEME_FILE" ]; then
    FIRE4NIX_THEME="$(fire4nix_read_trimmed_file "$FIRE4NIX_THEME_FILE" 2>/dev/null || true)"
    FIRE4NIX_THEME_SOURCE="file"
elif [ -n "${FIRE4NIX_THEME:-}" ]; then
    FIRE4NIX_THEME_SOURCE="environment"
else
    FIRE4NIX_THEME="${FIRE4NIX_THEME:-beta-dark}"
    ensure_default_config_file "$FIRE4NIX_THEME_FILE" "$FIRE4NIX_THEME"
    FIRE4NIX_THEME_SOURCE="default"
fi
export FIRE4NIX_THEME
export FIRE4NIX_THEME_SOURCE

if [ -f "$FIRE4NIX_ENGINE_FILE" ]; then
    FIRE4NIX_ENGINE="$(fire4nix_read_trimmed_file "$FIRE4NIX_ENGINE_FILE" 2>/dev/null || true)"
    FIRE4NIX_ENGINE_SOURCE="file"
elif [ -n "${FIRE4NIX_ENGINE:-}" ]; then
    FIRE4NIX_ENGINE_SOURCE="environment"
else
    FIRE4NIX_ENGINE="${FIRE4NIX_ENGINE:-auto}"
    ensure_default_config_file "$FIRE4NIX_ENGINE_FILE" "$FIRE4NIX_ENGINE"
    FIRE4NIX_ENGINE_SOURCE="default"
fi
export FIRE4NIX_ENGINE
export FIRE4NIX_ENGINE_SOURCE

# Backward-compatible aliases for the Fire4Nix runtime and wrapper.
: "${FIRE4NIX_HOME:=$APP_DIR}"
export FIRE4NIX_HOME
export FIRE4NIX_WRAPPER="${FIRE4NIX_WRAPPER:-$APP_DIR/firefox-framebuffer-wrapper.py}"
export FIRE4NIX_SOC="${FIRE4NIX_SOC:-rk3326}"
export FIRE4NIX_MAX_PERF="${FIRE4NIX_MAX_PERF:-1}"
export FIRE4NIX_LOW_QUALITY="${FIRE4NIX_LOW_QUALITY:-1}"
export FIRE4NIX_FORCE_VSYNC="${FIRE4NIX_FORCE_VSYNC:-1}"
export FIRE4NIX_AUDIO_BACKEND="${FIRE4NIX_AUDIO_BACKEND:-auto}"
export FIRE4NIX_NO_SLEEP="${FIRE4NIX_NO_SLEEP:-0}"
export FIRE4NIX_FRAME_SKIP="${FIRE4NIX_FRAME_SKIP:-1}"
export FIRE4NIX_INTERNAL_SCALE="${FIRE4NIX_INTERNAL_SCALE:-1}"
export FIRE4NIX_CPUSET="${FIRE4NIX_CPUSET:-0-3}"
export FIRE4NIX_USER_AGENT="${FIRE4NIX_USER_AGENT:-Mozilla/5.0 (Linux; Android 10; RK3326) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36}"
export FIRE4NIX_DARK_MODE="${FIRE4NIX_DARK_MODE:-1}"
export FIRE4NIX_THEME
export FIRE4NIX_THEME_FILE
export FIRE4NIX_ENGINE
export FIRE4NIX_ENGINE_FILE
export FIRE4NIX_UI_PROFILE
export FIRE4NIX_BETA
export FIRE4NIX_BETA_READY
export FIRE4NIX_HOME_URL
export FIRE4NIX_SEARCH_URL
export FIRE4NIX_PLATFORM
export FIRE4NIX_VERSION
export FIRE4NIX_SESSION_LABEL
export FIRE4NIX_STARTUP_HINT
export FIRE4NIX_BROWSER_MODE
export FIRE4NIX_CACHE_DIR
export FIRE4NIX_LOG_DIR
export FIRE4NIX_CONFIG_DIR="${FIRE4NIX_CONFIG_DIR:-$DEFAULT_CONFIG_DIR}"
export FIRE4NIX_LOG="${FIRE4NIX_LOG:-$FIRE4NIX_LOG_DIR/fire4nix.log}"
export SDL_RENDER_VSYNC="${SDL_RENDER_VSYNC:-${FIRE4NIX_FORCE_VSYNC:-1}}"
export MOZ_USE_XINPUT2=1
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"


# Make sure a usable runtime directory exists when launching from ES or SSH.
runtime_candidate="${XDG_RUNTIME_DIR:-}"
if [ -z "$runtime_candidate" ] || [ ! -d "$runtime_candidate" ] || [ ! -w "$runtime_candidate" ]; then
    if [ -d "/run/user/$(id -u 2>/dev/null || echo 0)" ] && [ -w "/run/user/$(id -u 2>/dev/null || echo 0)" ]; then
        export XDG_RUNTIME_DIR="/run/user/$(id -u)"
    else
        export XDG_RUNTIME_DIR="$FIRE4NIX_RUNTIME_DIR"
        mkdir -p "$XDG_RUNTIME_DIR" 2>/dev/null || true
    fi
fi

# Prefer Wayland when present, otherwise fall back cleanly.
if [ -n "${WAYLAND_DISPLAY:-}" ] || [ "${XDG_SESSION_TYPE:-}" = "wayland" ]; then
    export SDL_VIDEODRIVER="${SDL_VIDEODRIVER:-wayland}"
    export XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-wayland}"
    export GDK_BACKEND="${GDK_BACKEND:-wayland}"
    export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-wayland}"
export FIRE4NIX_COG_PLATFORM="${FIRE4NIX_COG_PLATFORM:-auto}"
export FIRE4NIX_COG_PLATFORM_PARAMS="${FIRE4NIX_COG_PLATFORM_PARAMS:-}"
export FIRE4NIX_WPE_DISPLAY="${FIRE4NIX_WPE_DISPLAY:-auto}"
export FIRE4NIX_COG_ALLOW_FILE_ACCESS="${FIRE4NIX_COG_ALLOW_FILE_ACCESS:-1}"
export FIRE4NIX_COG_ALLOW_PERMISSIONS="${FIRE4NIX_COG_ALLOW_PERMISSIONS:-1}"
export FIRE4NIX_COG_ENABLE_MEDIA="${FIRE4NIX_COG_ENABLE_MEDIA:-1}"
export FIRE4NIX_COG_CONSOLE="${FIRE4NIX_COG_CONSOLE:-1}"
    export MOZ_ENABLE_WAYLAND="${MOZ_ENABLE_WAYLAND:-1}"
elif [ -n "${DISPLAY:-}" ]; then
    export SDL_VIDEODRIVER="${SDL_VIDEODRIVER:-x11}"
    export XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-x11}"
fi

# Audio defaults: prefer ALSA when /dev/snd is available, otherwise inherit.
if [ -z "${SDL_AUDIODRIVER:-}" ] && { [ -e /dev/snd ] || [ -d /dev/snd ]; }; then
    export SDL_AUDIODRIVER=alsa
fi


if [ -z "${FIRE4NIX_START_PAGE:-}" ] && [ $# -gt 0 ]; then
    export FIRE4NIX_START_PAGE="$1"
    shift
fi

if [ -z "${FIRE4NIX_HOME_URL:-}" ] && [ -n "${FIRE4NIX_START_PAGE:-}" ]; then
    export FIRE4NIX_HOME_URL="$FIRE4NIX_START_PAGE"
fi

# Request maximum CPU clocks only when explicitly enabled.
if [ "${FIRE4NIX_SET_GOVERNOR:-${FIRE4NIX_SET_GOVERNOR:-0}}" = "1" ]; then
    for governor in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        if [ -w "$governor" ]; then
            echo performance > "$governor" 2>/dev/null || true
        fi
    done
fi

if [ -z "${FIRE4NIX_START_PAGE:-}" ] && [ $# -gt 0 ]; then
    export FIRE4NIX_START_PAGE="$1"
    shift
fi

# Normalize legacy engine labels into auto-detection.
if fire4nix_is_legacy_engine_label "${FIRE4NIX_ENGINE:-}"; then
    export FIRE4NIX_ENGINE="auto"
fi

export FIRE4NIX_START_PAGE="${FIRE4NIX_START_PAGE:-${FIRE4NIX_HOME_URL:-about:blank}}"
export FIRE4NIX_HOME_URL="${FIRE4NIX_HOME_URL:-$FIRE4NIX_START_PAGE}"

if [ -z "${FIRE4NIX_BROWSER_BINARY:-}" ] || [ "${FIRE4NIX_BROWSER_BINARY:-}" = "auto" ]; then
    export FIRE4NIX_BROWSER_BINARY="${FIRE4NIX_BINARY:-$APP_DIR/bin/browser.arm64}"
fi

selected_engine="$(fire4nix_resolve_engine "${FIRE4NIX_ENGINE:-auto}")"
export FIRE4NIX_ENGINE="$selected_engine"

{
    echo "[Fire4Nix] resolved_engine=${selected_engine}"
    echo "[Fire4Nix] launch_url=${FIRE4NIX_START_PAGE}"
    echo "[Fire4Nix] binary=${FIRE4NIX_BINARY:-auto}"
    echo "[Fire4Nix] wayland_display=${WAYLAND_DISPLAY:-none}"
    echo "[Fire4Nix] wpe_display=${WPE_DISPLAY:-auto}"
    echo "[Fire4Nix] cog_platform=${COG_PLATFORM_NAME:-auto}"
    cog_params="${COG_PLATFORM_PARAMS:-${FIRE4NIX_COG_PLATFORM_PARAMS:-}}"
    echo "[Fire4Nix] cog_platform_params=${cog_params}"
    echo "[Fire4Nix] xdg_runtime_dir=${XDG_RUNTIME_DIR:-none}"
    echo "[Fire4Nix] session_type=${XDG_SESSION_TYPE:-unknown}"
} >> "$LOG_FILE" 2>/dev/null || true

echo "[INFO] Launching with engine: ${selected_engine}"
echo "[Fire4Nix] launching engine=${selected_engine}" >> "$LOG_FILE"

if ! fire4nix_launch_engine "$selected_engine" "$FIRE4NIX_START_PAGE" "$@"; then
    echo "[ERROR] no launchable browser engine found" >&2
    echo "[Fire4Nix] no launchable browser engine found" >> "$LOG_FILE"
    exit 1
fi
