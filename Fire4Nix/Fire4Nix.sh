#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

# ZIP extraction on handhelds can drop executable bits. Recover them locally,
# then invoke the shell launchers explicitly so first launch does not depend on
# chmod having worked on the SD filesystem.
for target in     "$SCRIPT_DIR/scripts/run_browser.sh"     "$SCRIPT_DIR/scripts/wpe_platform_launch.sh"     "$SCRIPT_DIR/scripts/wpe_cog_launch.sh"     "$SCRIPT_DIR/bin/browser.arm64"     "$SCRIPT_DIR/bin/fire4nix-wpe-platform"
do
    [ -f "$target" ] && chmod +x "$target" 2>/dev/null || true
done

if [ -f "$SCRIPT_DIR/scripts/run_browser.sh" ]; then
    exec bash "$SCRIPT_DIR/scripts/run_browser.sh" "$@"
fi

if [ -x "$SCRIPT_DIR/bin/fire4nix-wpe-platform" ]; then
    exec "$SCRIPT_DIR/bin/fire4nix-wpe-platform" "$@"
fi

if [ -f "$SCRIPT_DIR/scripts/wpe_platform_launch.sh" ]; then
    exec bash "$SCRIPT_DIR/scripts/wpe_platform_launch.sh" "$@"
fi

if [ -x "$SCRIPT_DIR/bin/browser.arm64" ]; then
    exec "$SCRIPT_DIR/bin/browser.arm64" "$@"
fi

echo "Fire4Nix launcher could not find a runnable browser entry point." >&2
exit 1
