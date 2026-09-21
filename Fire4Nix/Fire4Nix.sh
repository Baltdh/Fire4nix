#!/bin/sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Keep the launcher self-contained so the user can just open this file
# from the copied ROCKNIX folder.
if [ -x "$SCRIPT_DIR/scripts/run_browser.sh" ]; then
    exec "$SCRIPT_DIR/scripts/run_browser.sh" "$@"
fi

if [ -x "$SCRIPT_DIR/bin/browser.arm64" ]; then
    exec "$SCRIPT_DIR/bin/browser.arm64" "$@"
fi

if [ -x "$SCRIPT_DIR/scripts/wpe_platform_launch.sh" ]; then
    exec "$SCRIPT_DIR/scripts/wpe_platform_launch.sh" "$@"
fi

echo "Fire4Nix launcher could not find a runnable browser entry point." >&2
exit 1
