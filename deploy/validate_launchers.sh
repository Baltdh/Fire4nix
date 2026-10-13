#!/usr/bin/env bash
# Static checks for launchers. Run on Linux in CI or a developer shell.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bash -n "$root/navegador-definitivo/scripts/fire4nix_env.sh"
bash -n "$root/navegador-definitivo/scripts/run_browser.sh"
bash -n "$root/navegador-definitivo/scripts/wpe_cog_launch.sh"
bash -n "$root/navegador-definitivo/scripts/wpe_platform_launch.sh"
bash -n "$root/deploy/test_engine_entrypoints.sh"
sh -n "$root/navegador-definitivo/Fire4Nix.sh"
sh -n "$root/deploy/Fire4Nix-ROCKNIX.sh"
sh -n "$root/deploy/Fire4Nix-WPE-Diagnostico.sh"
if grep -Eq '^[[:space:]]*"\$\{FIRE4NIX_HOME:-\$APP_DIR\}/bin/fire4nix-wpe-platform"' "$root/navegador-definitivo/scripts/fire4nix_env.sh"; then
 echo "ERROR: WPE shell wrapper must not be considered native WPE binary" >&2
 exit 1
fi
bash "$root/deploy/test_portable_launcher.sh"
bash "$root/deploy/test_engine_entrypoints.sh"
echo "Launcher syntax and WPE wrapper regression checks passed"
