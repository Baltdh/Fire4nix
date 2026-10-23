#!/usr/bin/env bash
# Host-only launch-path tests with a fake executable, not WebKit or R36H.
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
root="$tmp/SD Card/Fire4Nix"
mkdir -p "$root/bin" "$root/runtime/lib" \
  "$root/runtime/libexec/wpe-webkit-2.0" "$root/logs" "$root/www"
cp "$repo/installer/Fire4Nix-Iniciar.sh" "$root/Fire4Nix-Iniciar.sh"
cat > "$root/bin/fire4nix-native-aarch64" <<'EOF'
#!/bin/sh
printf 'exec=%s\ninjected=%s\ninspector=%s\n' \
  "${WEBKIT_EXEC_PATH:-absent}" \
  "${WEBKIT_INJECTED_BUNDLE_PATH:-unset}" \
  "${WEBKIT_INSPECTOR_RESOURCES_PATH:-unset}" > "$FIRE4NIX_ENV_CAPTURE"
EOF
chmod +x "$root/bin/fire4nix-native-aarch64"
printf 'fake WPE ELF metadata fixture\n' > "$root/runtime/lib/libWPEWebKit-2.0.so.1"
for process in WPEWebProcess WPENetworkProcess; do
  printf 'mock subprocess, not executed\n' > "$root/runtime/libexec/wpe-webkit-2.0/$process"
done
report="$root/runtime/BUILD-REPORT.txt"
bundle="$root/runtime/lib/wpe-webkit-2.0/injected-bundle"
resource="$root/runtime/share/wpe-webkit-2.0/inspector.gresource"
capture="$tmp/env-capture.txt"
launch() {
  (cd "$tmp" && env \
    FIRE4NIX_ENV_CAPTURE="$capture" \
    FIRE4NIX_GAMEPAD=0 \
    FIRE4NIX_LOG_DIR="$root/logs" \
    WEBKIT_INJECTED_BUNDLE_PATH=/foreign/webkit/injected \
    WEBKIT_INSPECTOR_RESOURCES_PATH=/foreign/webkit/inspector.gresource \
    sh "$root/Fire4Nix-Iniciar.sh" --check-library > "$tmp/launch.log" 2>&1)
}
assert_reject() {
  rm -f "$capture"
  if launch; then
    echo "FAIL: unsafe WPE assets accepted ($1)" >&2
    exit 1
  fi
  test ! -e "$capture"
  grep -Fq "$1" "$tmp/launch.log"
}
# A real packaged WPE 2.54.1 runtime must use private relocatable paths,
# not system defaults or unrelated inherited browser environments.
cat > "$report" <<'EOF'
GPU_PROCESS_PROFILE=disabled_verified_wayland
WPE_INSTALLED_ASSETS_PROFILE=strict
WPE_INSTALLED_ASSETS_STATUS=copied_and_static_elf_checked
EOF
mkdir -p "$bundle" "$(dirname "$resource")"
printf 'WPE module fixture\n' > "$bundle/libWPEInjectedBundle.so"
printf 'WPE inspector resource fixture\n' > "$resource"
launch
grep -Fxq "exec=$root/runtime/libexec/wpe-webkit-2.0" "$capture"
grep -Fxq "injected=$bundle" "$capture"
grep -Fxq "inspector=$resource" "$capture"

rm -f "$resource"
assert_reject 'WPE injected-bundle or inspector resource missing/unsafe'
printf 'WPE inspector resource fixture\n' > "$resource"
mv "$bundle/libWPEInjectedBundle.so" "$tmp/regular-module"
ln -s "$tmp/regular-module" "$bundle/libWPEInjectedBundle.so"
assert_reject 'WPE injected-bundle or inspector resource missing/unsafe'
rm "$bundle/libWPEInjectedBundle.so"
mv "$tmp/regular-module" "$bundle/libWPEInjectedBundle.so"

sed 's/WPE_INSTALLED_ASSETS_STATUS=copied_and_static_elf_checked/WPE_INSTALLED_ASSETS_STATUS=not_installed/' "$report" > "$tmp/bad-report"
cp "$tmp/bad-report" "$report"
assert_reject 'Strict WPE runtime assets were not verified'
cat > "$report" <<'EOF'
GPU_PROCESS_PROFILE=disabled_verified_wayland
WPE_INSTALLED_ASSETS_PROFILE=strict
WPE_INSTALLED_ASSETS_PROFILE=optional
WPE_INSTALLED_ASSETS_STATUS=copied_and_static_elf_checked
EOF
assert_reject 'Invalid or conflicting WPE installed-assets profile'

# An older runtime without injected resources should never inherit foreign
# WEBKIT_* paths from the calling menu, PortMaster, or shell.
rm -rf "$root/runtime/lib/wpe-webkit-2.0" "$root/runtime/share"
cat > "$report" <<'EOF'
GPU_PROCESS_PROFILE=disabled_verified_wayland
EOF
launch
grep -Fxq 'injected=unset' "$capture"
grep -Fxq 'inspector=unset' "$capture"
grep -Fq 'wpe_installed_assets=legacy_absent' "$tmp/launch.log"

cat > "$report" <<'EOF'
GPU_PROCESS_PROFILE=disabled_verified_wayland
WPE_INSTALLED_ASSETS_PROFILE=strict
WPE_INSTALLED_ASSETS_STATUS=copied_and_static_elf_checked
EOF
assert_reject 'WPE runtime reported installed assets but files are absent'

echo 'WPE_LAUNCHER_PRIVATE_ASSET_PATHS=PASS_HOST_MOCK_ONLY'
