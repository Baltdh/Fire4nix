#!/bin/bash
set -euo pipefail
umask 022

REAL_SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$0" 2>/dev/null || printf '%s\n' "$0")"
SCRIPT_DIR="$(cd "$(dirname "$REAL_SCRIPT_PATH")" && pwd)"
APP_NAME="Fire4Nix"
SYSTEM_NAME="fire4nix"
PLATFORM_TAG="fire4nix"
THEME_NAME="fire4nix"
LAUNCHER_NAME="Fire4Nix Browser"
INSTALL_DIR="$SCRIPT_DIR"
source "$INSTALL_DIR/scripts/fire4nix_env.sh"
ES_CFG="/etc/emulationstation/es_systems.cfg"
ES_CFG_DUAL="/etc/emulationstation/es_systems.cfg.dual"
ES_THEME_ROOT="/etc/emulationstation/themes"
resolve_config_root() {
    if [ -n "${FIRE4NIX_CONFIG_DIR:-}" ]; then
        printf '%s\n' "$FIRE4NIX_CONFIG_DIR"
        return 0
    fi
    if [ -n "${XDG_CONFIG_HOME:-}" ]; then
        printf '%s\n' "$XDG_CONFIG_HOME/fire4nix"
        return 0
    fi
    if [ -n "${HOME:-}" ]; then
        printf '%s\n' "$HOME/.config/fire4nix"
        return 0
    fi
    if [ -d /storage ] || [ -w /storage ] 2>/dev/null; then
        printf '%s\n' "/storage/.config/fire4nix"
        return 0
    fi
    printf '%s\n' "$INSTALL_DIR/.fire4nix"
}


resolve_runtime_dir() {
    if [ -n "${FIRE4NIX_RUNTIME_DIR:-}" ]; then
        printf '%s\n' "$FIRE4NIX_RUNTIME_DIR"
        return 0
    fi
    if [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -d "${XDG_RUNTIME_DIR:-}" ] && [ -w "${XDG_RUNTIME_DIR:-}" ]; then
        printf '%s\n' "$XDG_RUNTIME_DIR"
        return 0
    fi
    local candidate="/run/user/$(id -u 2>/dev/null || echo 0)"
    if [ -d "$candidate" ] && [ -w "$candidate" ]; then
        printf '%s\n' "$candidate"
        return 0
    fi
    printf '%s\n' "$INSTALL_DIR/.fire4nix/runtime"
}
LOG_RETENTION_DAYS="${FIRE4NIX_LOG_RETENTION_DAYS:-14}"

cleanup_old_logs() {
    local log_dir="$CONFIG_ROOT/logs"
    local root_dir="$CONFIG_ROOT"
    [ -d "$log_dir" ] || return 0
    find "$log_dir" -type f \( -name '*.log' -o -name '*.log.*' -o -name '*.bak' -o -name '*.old' -o -name '*.tmp' -o -name '*.trace' \) -mtime +"$LOG_RETENTION_DAYS" -delete 2>/dev/null || true
    find "$root_dir" -maxdepth 1 -type f \( -name '*.log' -o -name '*.log.*' -o -name '*.bak' -o -name '*.old' -o -name '*.tmp' -o -name '*.trace' \) -mtime +"$LOG_RETENTION_DAYS" -delete 2>/dev/null || true
}

DEFAULT_CONFIG_ROOT="$(resolve_config_root)"
if ! mkdir -p "$DEFAULT_CONFIG_ROOT/cache" "$DEFAULT_CONFIG_ROOT/logs" 2>/dev/null; then
    DEFAULT_CONFIG_ROOT="$INSTALL_DIR/.fire4nix"
    mkdir -p "$DEFAULT_CONFIG_ROOT/cache" "$DEFAULT_CONFIG_ROOT/logs" 2>/dev/null || true
fi
CONFIG_ROOT="$DEFAULT_CONFIG_ROOT"
export FIRE4NIX_CONFIG_DIR="$CONFIG_ROOT"
fire4nix_bootstrap_environment "$INSTALL_DIR"
fire4nix_stage_reference_pack "$INSTALL_DIR" "$CONFIG_ROOT"
cleanup_old_logs
fire4nix_log_reference_summary "$FIRE4NIX_REFERENCE_ROOT"
export FIRE4NIX_LOG_DIR="${FIRE4NIX_LOG_DIR:-$CONFIG_ROOT/logs}"
export FIRE4NIX_LOG="${FIRE4NIX_LOG:-$FIRE4NIX_LOG_DIR/fire4nix-install.log}"
export FIRE4NIX_CONFIG_DIR="${FIRE4NIX_CONFIG_DIR:-$CONFIG_ROOT}"
export FIRE4NIX_CONFIG_DIR
export FIRE4NIX_CONF="${FIRE4NIX_CONF:-$CONFIG_ROOT/fire4nix.conf}"
export FIRE4NIX_AUDIO_BACKEND="${FIRE4NIX_AUDIO_BACKEND:-auto}"

export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
RUNTIME_DIR="$(resolve_runtime_dir)"
if ! mkdir -p "$RUNTIME_DIR" 2>/dev/null; then
    RUNTIME_DIR="$INSTALL_DIR/.fire4nix/runtime"
    mkdir -p "$RUNTIME_DIR" 2>/dev/null || true
fi
chmod 700 "$RUNTIME_DIR" 2>/dev/null || true
export FIRE4NIX_RUNTIME_DIR="${FIRE4NIX_RUNTIME_DIR:-$RUNTIME_DIR}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-$RUNTIME_DIR}"
export MOZ_ENABLE_WAYLAND="${MOZ_ENABLE_WAYLAND:-1}"
export GDK_BACKEND="${GDK_BACKEND:-wayland}"
export SDL_VIDEODRIVER="${SDL_VIDEODRIVER:-wayland}"
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-wayland}"


LAUNCHER_PATH="$INSTALL_DIR/$LAUNCHER_NAME.f4a"
BIN_LINK="/usr/local/bin/fire4nix"
LEGACY_LINK="/usr/local/bin/fire4arkos"
RUNNER_LINK="/usr/local/bin/fire4nix-browser"
WPE_LINK="/usr/local/bin/fire4nix-wpe-platform"

self_elevate() {
    if [ "$(id -u)" -eq 0 ]; then
        return 0
    fi
    if command -v sudo >/dev/null 2>&1; then
        echo "$APP_NAME installer needs root privileges. Re-running with sudo..."
        exec sudo -E bash "$REAL_SCRIPT_PATH" "$@"
    fi
    echo "Root privileges are required to install $APP_NAME." >&2
    exit 1
}

usage() {
    cat <<'EOF'
Fire4Nix installer

Usage:
  Install-Fire4Nix.sh [--browser-only|--theme-only|--uninstall|--help]

Options:
  --browser-only   Install launcher, links and ES entry; skip theme copy.
  --theme-only     Install only theme assets and ES entry.
  --uninstall      Remove launcher links and ES entry.
  --help           Show this help text.
EOF
}

for arg in "$@"; do
    case "$arg" in
        --help|-h)
            usage
            exit 0
            ;;
    esac
done

log() { printf '[%s] %s\n' "$APP_NAME" "$*"; }
warn() { printf '[%s] %s\n' "$APP_NAME" "$*" >&2; }

ensure_exec() {
    for target in "$@"; do
        [ -e "$target" ] || continue
        chmod +x "$target" 2>/dev/null || true
    done
}

write_launcher() {
    cat > "$LAUNCHER_PATH" <<'EOF'
#!/bin/sh
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export FIRE4NIX_HOME="${FIRE4NIX_HOME:-$SCRIPT_DIR}"

resolve_config_root() {
    if [ -n "${FIRE4NIX_CONFIG_DIR:-}" ]; then
        printf '%s\n' "$FIRE4NIX_CONFIG_DIR"
        return 0
    fi
    if [ -n "${XDG_CONFIG_HOME:-}" ]; then
        printf '%s\n' "$XDG_CONFIG_HOME/fire4nix"
        return 0
    fi
    if [ -n "${HOME:-}" ]; then
        printf '%s\n' "$HOME/.config/fire4nix"
        return 0
    fi
    if [ -d /storage ] || [ -w /storage ] 2>/dev/null; then
        printf '%s\n' "/storage/.config/fire4nix"
        return 0
    fi
    printf '%s\n' "$SCRIPT_DIR/.fire4nix"
}

DEFAULT_CONFIG_DIR="$(resolve_config_root)"
if ! mkdir -p "$DEFAULT_CONFIG_DIR/cache" "$DEFAULT_CONFIG_DIR/logs" 2>/dev/null; then
    DEFAULT_CONFIG_DIR="$SCRIPT_DIR/.fire4nix"
    mkdir -p "$DEFAULT_CONFIG_DIR/cache" "$DEFAULT_CONFIG_DIR/logs" 2>/dev/null || true
fi
: "${FIRE4NIX_CONFIG_DIR:=$DEFAULT_CONFIG_DIR}"
export FIRE4NIX_CONFIG_DIR
export FIRE4NIX_CONF="${FIRE4NIX_CONF:-$FIRE4NIX_CONFIG_DIR/fire4nix.conf}"
export FIRE4NIX_CACHE_DIR="${FIRE4NIX_CACHE_DIR:-$FIRE4NIX_CONFIG_DIR/cache}"
export FIRE4NIX_LOG_DIR="${FIRE4NIX_LOG_DIR:-$FIRE4NIX_CONFIG_DIR/logs}"
export FIRE4NIX_LOG="${FIRE4NIX_LOG:-$FIRE4NIX_LOG_DIR/fire4nix.log}"
export FIRE4NIX_BINARY="${FIRE4NIX_BINARY:-$SCRIPT_DIR/bin/browser.arm64}"
export FIRE4NIX_AUDIO_BACKEND="${FIRE4NIX_AUDIO_BACKEND:-auto}"

export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
if [ -z "${FIRE4NIX_RUNTIME_DIR:-}" ]; then
    FIRE4NIX_RUNTIME_DIR="$(resolve_runtime_dir)"
fi
export FIRE4NIX_RUNTIME_DIR
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-${FIRE4NIX_RUNTIME_DIR}}"
export MOZ_ENABLE_WAYLAND="${MOZ_ENABLE_WAYLAND:-1}"
export GDK_BACKEND="${GDK_BACKEND:-wayland}"
export SDL_VIDEODRIVER="${SDL_VIDEODRIVER:-wayland}"
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-wayland}"

mkdir -p "$XDG_RUNTIME_DIR" 2>/dev/null || true
chmod 700 "$XDG_RUNTIME_DIR" 2>/dev/null || true
if [ -z "${SDL_AUDIODRIVER:-}" ] && { [ -e /dev/snd ] || [ -d /dev/snd ]; }; then
    export SDL_AUDIODRIVER=alsa
fi
cleanup_stale_logs() {
    log_dir="$FIRE4NIX_LOG_DIR"
    [ -d "$log_dir" ] || return 0
    find "$log_dir" -type f \( -name '*.log' -o -name '*.log.*' -o -name '*.bak' -o -name '*.old' \) -mtime +30 -delete 2>/dev/null || true
}
cleanup_stale_logs
if [ -z "${XDG_RUNTIME_DIR:-}" ]; then
    if [ -d "/run/user/$(id -u 2>/dev/null || echo 0)" ] && [ -w "/run/user/$(id -u 2>/dev/null || echo 0)" ]; then
        export XDG_RUNTIME_DIR="/run/user/$(id -u)"
    else
        export XDG_RUNTIME_DIR="$DEFAULT_CONFIG_DIR/runtime"
        mkdir -p "$XDG_RUNTIME_DIR" 2>/dev/null || true
    fi
fi
exec "$SCRIPT_DIR/scripts/run_browser.sh" "$@"
EOF
    chmod +x "$LAUNCHER_PATH"
}

install_links() {
    mkdir -p /usr/local/bin 2>/dev/null || true
    ln -sf "$INSTALL_DIR/fire4nix" "$BIN_LINK"
    ln -sf "$INSTALL_DIR/scripts/run_browser.sh" "$RUNNER_LINK"
    ln -sf "$INSTALL_DIR/scripts/wpe_platform_launch.sh" "$WPE_LINK"
}

remove_links() {
    rm -f "$BIN_LINK" "$RUNNER_LINK" "$LEGACY_LINK" "$WPE_LINK"
    rm -f "$LAUNCHER_PATH"
}

install_theme() {
    [ -d "$INSTALL_DIR/theme" ] || return 0
    [ -d "$ES_THEME_ROOT" ] || return 0
    for base in "$ES_THEME_ROOT"/*/; do
        [ -d "$base" ] || continue
        dest="${base%/}/$THEME_NAME"
        mkdir -p "$dest"
        cp -r "$INSTALL_DIR/theme/"* "$dest/" 2>/dev/null || true
    done
}

register_es() {
    for cfg in "$ES_CFG" "$ES_CFG_DUAL"; do
        [ -f "$cfg" ] || continue
        python3 "$INSTALL_DIR/install-es-system.py" \
            --cfg-file "$cfg" \
            --install-dir "$INSTALL_DIR" \
            --system-name "$SYSTEM_NAME" \
            --platform-tag "$PLATFORM_TAG" \
            --theme-name "$THEME_NAME" \
            --fullname "$APP_NAME Browser"
    done
}

remove_es() {
    for cfg in "$ES_CFG" "$ES_CFG_DUAL"; do
        [ -f "$cfg" ] || continue
        python3 "$INSTALL_DIR/install-es-system.py" \
            --cfg-file "$cfg" \
            --remove \
            --system-name "$SYSTEM_NAME"
    done
}


cleanup_stale_logs() {
    log_dir="$CONFIG_ROOT/logs"
    retention_days="${FIRE4NIX_LOG_RETENTION_DAYS:-14}"
    [ -d "$log_dir" ] || return 0
    find "$log_dir" -type f \( -name '*.log' -o -name '*.log.*' -o -name '*.bak' -o -name '*.old' -o -name '*.tmp' \) -mtime +"$retention_days" -delete 2>/dev/null || true
    find "$CONFIG_ROOT" -maxdepth 1 -type f \( -name '*.log' -o -name '*.log.*' -o -name '*.bak' -o -name '*.old' -o -name '*.tmp' \) -mtime +"$retention_days" -delete 2>/dev/null || true
    find "$CONFIG_ROOT" -type d -name '__pycache__' -prune -exec rm -rf {} + 2>/dev/null || true
    find "$CONFIG_ROOT" -type f -name '*.pyc' -delete 2>/dev/null || true
    find "$CONFIG_ROOT" -type f \( -name '.DS_Store' -o -name 'Thumbs.db' \) -delete 2>/dev/null || true
}

preflight_checks() {
    if [ -z "${WAYLAND_DISPLAY:-}" ] && [ -z "${DISPLAY:-}" ]; then
        warn "No Wayland/X11 session detected. ROCKNIX will need a compositor session at launch time."
    fi
    if [ -z "${XDG_RUNTIME_DIR:-}" ]; then
        warn "XDG_RUNTIME_DIR is not set yet; launcher will create a fallback runtime directory."
    elif [ ! -d "${XDG_RUNTIME_DIR:-}" ] || [ ! -w "${XDG_RUNTIME_DIR:-}" ]; then
        warn "XDG_RUNTIME_DIR exists but is not writable; launcher will fall back to the config runtime directory."
    fi
    if [ "${XDG_SESSION_TYPE:-}" = "wayland" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
        warn "Wayland session detected without WAYLAND_DISPLAY; launcher will force the Wayland path."
    fi
    local caller="${SUDO_USER:-${USER:-}}"
    if [ -n "$caller" ] && command -v id >/dev/null 2>&1; then
        if ! id -nG "$caller" 2>/dev/null | grep -qw audio; then
            warn "User '$caller' is not in the audio group; sound may fail until permissions are fixed."
        fi
    fi
    if [ ! -e /dev/snd ]; then
        warn "/dev/snd is not visible on this system; audio backend will fall back or stay muted."
    fi
}

verify_install() {
    printf 'installed_launcher=%s\n' "$LAUNCHER_PATH"
    printf 'config_root=%s\n' "$CONFIG_ROOT"
    printf 'runtime_dir=%s\n' "$CONFIG_ROOT/runtime"
    printf 'binary_link=%s\n' "$BIN_LINK"
    printf 'runner_link=%s\n' "$RUNNER_LINK"
    printf 'wpe_link=%s\n' "$WPE_LINK"
    printf 'wayland_hint=%s\n' "MOZ_ENABLE_WAYLAND=1"
    [ -x "$INSTALL_DIR/scripts/run_browser.sh" ] || warn "launcher script is not executable"
    [ -f "$INSTALL_DIR/bin/browser.arm64" ] || warn "browser binary is missing"
    [ -x "$INSTALL_DIR/bin/browser.arm64" ] || warn "browser binary exists but lost execute permission; installer will try to recover it"
    [ -x "$LAUNCHER_PATH" ] || warn "launcher file exists but is not executable"
}

self_elevate "$@"

preflight_checks

mode="full"
for arg in "$@"; do
    case "$arg" in
        --help|-h)
            usage
            exit 0
            ;;
        --browser-only)
            mode="browser"
            ;;
        --theme-only)
            mode="theme"
            ;;
        --uninstall)
            mode="uninstall"
            ;;
        *)
            ;;
    esac
done

mkdir -p "$CONFIG_ROOT/cache" "$CONFIG_ROOT/logs" 2>/dev/null || true
ensure_exec "$INSTALL_DIR/scripts/run_browser.sh" "$INSTALL_DIR/scripts/browser_manager.sh" "$INSTALL_DIR/scripts/engine_manager.sh" "$INSTALL_DIR/scripts/theme_manager.sh" "$INSTALL_DIR/scripts/install-es-system.py" "$INSTALL_DIR/scripts/firefox-framebuffer-wrapper.py" "$INSTALL_DIR/scripts/wpe_platform_launch.sh" "$INSTALL_DIR/fire4nix" "$INSTALL_DIR/bin/browser.arm64"

if [ "$mode" = "uninstall" ]; then
    log "Removing $APP_NAME beta files from the system..."
    remove_links
    remove_es || warn "Unable to remove ES entry from one or more configs"
    log "Uninstall complete."
    exit 0
fi

if [ -f "$INSTALL_DIR/fire4nix.conf" ] && [ ! -f "$CONFIG_ROOT/fire4nix.conf" ]; then
    cp -f "$INSTALL_DIR/fire4nix.conf" "$CONFIG_ROOT/fire4nix.conf" 2>/dev/null || true
fi

write_launcher
install_links

case "$mode" in
    browser)
        log "Installing browser-only package..."
        register_es || warn "Unable to update EmulationStation config"
        ;;
    theme)
        log "Installing theme-only package..."
        install_theme
        register_es || warn "Unable to update EmulationStation config"
        ;;
    *)
        log "Installing full beta package..."
        install_theme
        register_es || warn "Unable to update EmulationStation config"
        ;;
esac

cleanup_stale_logs
verify_install
log "Ready for ROCKNIX beta sequencefix."
printf 'Restart EmulationStation to see %s.\n' "$APP_NAME"
