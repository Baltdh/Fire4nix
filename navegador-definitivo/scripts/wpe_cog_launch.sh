#!/bin/bash
set -euo pipefail

REAL_SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$0" 2>/dev/null || printf '%s
' "$0")"
SCRIPT_DIR="$(cd "$(dirname "$REAL_SCRIPT_PATH")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=/dev/null
source "$APP_DIR/scripts/fire4nix_env.sh"
fire4nix_bootstrap_environment "$APP_DIR"
fire4nix_log_reference_summary "$FIRE4NIX_REFERENCE_ROOT"
fire4nix_wpe_runtime_env
fire4nix_export_wpe_common_env

target="${1:-${FIRE4NIX_START_PAGE:-${FIRE4NIX_HOME_URL:-about:home}}}"
shift || true

export FIRE4NIX_ENGINE="${FIRE4NIX_ENGINE:-cog}"
export FIRE4NIX_COG_PLATFORM="${FIRE4NIX_COG_PLATFORM:-auto}"
export FIRE4NIX_COG_PLATFORM_PARAMS="${FIRE4NIX_COG_PLATFORM_PARAMS:-}"
export FIRE4NIX_COG_ALLOW_FILE_ACCESS="${FIRE4NIX_COG_ALLOW_FILE_ACCESS:-1}"
export FIRE4NIX_COG_ALLOW_PERMISSIONS="${FIRE4NIX_COG_ALLOW_PERMISSIONS:-1}"
export FIRE4NIX_COG_ENABLE_MEDIA="${FIRE4NIX_COG_ENABLE_MEDIA:-1}"
export FIRE4NIX_COG_CONSOLE="${FIRE4NIX_COG_CONSOLE:-1}"

export FIRE4NIX_ENGINE_PROFILE_DIR="$(fire4nix_apply_engine_selection cog)"
export FIRE4NIX_ENGINE_SELECTED="cog"
exec fire4nix_launch_engine cog "$target" "$@"
