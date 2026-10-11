#!/bin/bash
set -euo pipefail

REAL_SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$0" 2>/dev/null || printf '%s\n' "$0")"
SCRIPT_DIR="$(cd "$(dirname "$REAL_SCRIPT_PATH")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=/dev/null
. "$APP_DIR/scripts/fire4nix_env.sh"

fire4nix_bootstrap_environment "$APP_DIR"
fire4nix_log_reference_summary "$FIRE4NIX_REFERENCE_ROOT"
fire4nix_export_wpe_common_env
export FIRE4NIX_WPE_PLATFORM_BINARY="${FIRE4NIX_WPE_PLATFORM_BINARY:-$(fire4nix_wpe_platform_binary)}"

target="${1:-${FIRE4NIX_START_PAGE:-${FIRE4NIX_HOME_URL:-$(fire4nix_default_home_url)}}}"
shift || true

export FIRE4NIX_ENGINE_PRIORITY="${FIRE4NIX_ENGINE_PRIORITY:-wpe-platform,cog,chromium,firefox,browser.arm64}"
export FIRE4NIX_ENGINE_SELECTED="wpe-platform"

exec fire4nix_launch_engine "wpe-platform" "$target" "$@"
