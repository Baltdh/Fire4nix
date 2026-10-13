#!/bin/bash
set -euo pipefail

REAL_SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$0" 2>/dev/null || printf '%s\n' "$0")"
SCRIPT_DIR="$(cd "$(dirname "$REAL_SCRIPT_PATH")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$APP_DIR/scripts/fire4nix_env.sh"
fire4nix_bootstrap_environment "$APP_DIR"
fire4nix_log_reference_summary "$FIRE4NIX_REFERENCE_ROOT"
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
    printf '%s\n' "$APP_DIR/.fire4nix"
}

CONFIG_DIR="$(resolve_config_root)"
: "${FIRE4NIX_CONFIG_DIR:=$CONFIG_DIR}"
export FIRE4NIX_CONFIG_DIR
export FIRE4NIX_CONF="${FIRE4NIX_CONF:-$CONFIG_DIR/fire4nix.conf}"
THEME_FILE="${FIRE4NIX_THEME_FILE:-$CONFIG_DIR/theme.conf}"
DEFAULT_THEME="${FIRE4NIX_THEME:-beta-dark}"
ALLOWED_THEMES="beta-dark beta-light compact-dark compact-light"

mkdir -p "$CONFIG_DIR" 2>/dev/null || true

usage() {
    cat <<'EOF'
Fire4Nix theme manager

Usage:
  theme_manager.sh get
  theme_manager.sh set <theme-name>
  theme_manager.sh reset
  theme_manager.sh list
  theme_manager.sh status
EOF
}

trim_value() {
    printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

is_allowed_theme() {
    case " $ALLOWED_THEMES " in
        *" $1 "*) return 0 ;;
        *) return 1 ;;
    esac
}

current_theme() {
    if [ -f "$THEME_FILE" ]; then
        value="$(trim_value "$(fire4nix_read_trimmed_file "$THEME_FILE" 2>/dev/null || true)")"
        if [ -n "$value" ] && is_allowed_theme "$value"; then
            printf '%s' "$value"
            return 0
        fi
    fi

    if [ -n "${FIRE4NIX_THEME:-}" ] && is_allowed_theme "$(trim_value "$FIRE4NIX_THEME")"; then
        trim_value "$FIRE4NIX_THEME"
        return 0
    fi

    printf '%s' "$DEFAULT_THEME"
}

theme_source() {
    if [ -f "$THEME_FILE" ] && [ -n "$(fire4nix_read_trimmed_file "$THEME_FILE" 2>/dev/null || true)" ]; then
        printf '%s' "file"
        return 0
    fi
    if [ -n "${FIRE4NIX_THEME:-}" ]; then
        printf '%s' "environment"
        return 0
    fi
    printf '%s' "default"
}

save_theme() {
    value="$(trim_value "$1")"
    if [ -z "$value" ]; then
        printf 'theme cannot be empty\n' >&2
        exit 2
    fi
    if ! is_allowed_theme "$value"; then
        printf 'unknown theme: %s\n' "$value" >&2
        exit 2
    fi
    printf '%s\n' "$value" > "$THEME_FILE"
    printf 'theme=%s\n' "$value"
}

case "${1:-get}" in
    get)
        current_theme
        printf '\n'
        ;;
    set)
        shift || true
        if [ $# -eq 0 ]; then
            usage
            exit 2
        fi
        save_theme "$*"
        ;;
    reset)
        rm -f "$THEME_FILE"
        printf 'theme=%s\n' "$DEFAULT_THEME"
        ;;
    list)
        cat <<EOF
beta-dark
beta-light
compact-dark
compact-light
EOF
        ;;
    status)
        printf 'theme=%s\n' "$(current_theme)"
        printf 'theme_source=%s\n' "$(theme_source)"
        printf 'theme_file=%s\n' "$THEME_FILE"
        ;;
    *)
        usage
        exit 2
        ;;
esac
