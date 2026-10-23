#!/bin/sh
# Host-only Ports and install-once checks: all "browser" executables are mocks.
# The test does not load WebKit, mount SD cards, or modify the ROCKNIX device.
set -eu
BASE=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P) || exit 2
T=$(mktemp -d)
trap 'rm -rf "$T"' 0
P="$T/ports with spaces"
APP="$P/Fire4Nix"
CHILD="$APP/runtime/libexec/wpe-webkit-2.0"
mkdir -p "$APP/bin" "$APP/runtime/lib" "$CHILD"
cp "$BASE/installer/Fire4Nix-Direto.sh" "$P/Fire4Nix-Direto.sh"
printf 'mock-WPE\n' > "$APP/runtime/lib/libWPEWebKit-2.0.so.1"
printf 'mock-AArch64\n' > "$APP/bin/fire4nix-native-aarch64"
for name in WPEWebProcess WPENetworkProcess; do
    printf 'mock-%s\n' "$name" > "$CHILD/$name"
done
cat > "$APP/Fire4Nix-Iniciar.sh" <<'MOCK'
#!/bin/sh
printf 'PORTS_MOCK_LAUNCHED=%s\n' "$*" >> "$FIRE4NIX_TEST_TRACE"
exit 0
MOCK
export FIRE4NIX_TEST_TRACE="$T/ports-called.txt"
LAUNCH="$P/Fire4Nix-Direto.sh"
run_ports() {
    FIRE4NIX_ROOT="$APP" sh "$LAUNCH" > "$T/ports-stdout.txt" 2>&1
}
ports_refuse() {
    rm -f "$FIRE4NIX_TEST_TRACE"
    set +e
    run_ports
    rc=$?
    set -e
    test "$rc" -eq 127 || { echo "Ports refusal returned $rc (expected 127)" >&2; exit 1; }
    test ! -e "$FIRE4NIX_TEST_TRACE"
}
printf 'GPU_PROCESS_PROFILE=disabled_verified_wayland\n' > "$APP/runtime/BUILD-REPORT.txt"
run_ports
grep -Fxq 'real_browser_exit=0' "$P/Fire4Nix-PORTS-ultimo.txt"
grep -Fq 'PORTS_MOCK_LAUNCHED=--open' "$FIRE4NIX_TEST_TRACE"
rm "$APP/runtime/BUILD-REPORT.txt"
ports_refuse
grep -Fq 'missing= WPEGPUProcess' "$P/Fire4Nix-PORTS-ultimo.txt"
printf 'GPU_PROCESS_PROFILE=disabled_verified_wayland\nGPU_PROCESS_PROFILE=enabled_verified\n' > "$APP/runtime/BUILD-REPORT.txt"
ports_refuse
grep -Fq 'skipped_invalid_gpu_profile=' "$P/Fire4Nix-PORTS-ultimo.txt"
printf 'GPU_PROCESS_PROFILE=disabled\n' > "$APP/runtime/BUILD-REPORT.txt"
ports_refuse
rm "$APP/runtime/BUILD-REPORT.txt"
printf 'GPU_PROCESS_PROFILE=disabled_verified_wayland\n' > "$T/external.txt"
ln -s "$T/external.txt" "$APP/runtime/BUILD-REPORT.txt"
ports_refuse
grep -Fq 'skipped_invalid_gpu_report=' "$P/Fire4Nix-PORTS-ultimo.txt"
rm "$APP/runtime/BUILD-REPORT.txt"
printf 'GPU_PROCESS_PROFILE=disabled_verified_wayland\n' > "$APP/runtime/BUILD-REPORT.txt"
rm "$CHILD/WPENetworkProcess"
ports_refuse
grep -Fq 'WPENetworkProcess' "$P/Fire4Nix-PORTS-ultimo.txt"
printf 'mock-network\n' > "$CHILD/WPENetworkProcess"
printf 'GPU_PROCESS_PROFILE=enabled_verified\n' > "$APP/runtime/BUILD-REPORT.txt"
ports_refuse
printf 'mock-gpu\n' > "$CHILD/WPEGPUProcess"
run_ports
grep -Fxq 'real_browser_exit=0' "$P/Fire4Nix-PORTS-ultimo.txt"
rm "$APP/runtime/BUILD-REPORT.txt"
run_ports
grep -Fxq 'real_browser_exit=0' "$P/Fire4Nix-PORTS-ultimo.txt"

# Exercise the REAL installer/launcher shell logic with an inert mock native
# binary. The filesystem and ROMS root exist only under mktemp.
PKG="$T/package with spaces"
PACKAGE="$PKG/Fire4Nix"
ROM="$T/roms"
mkdir -p "$PACKAGE/bin" "$PACKAGE/runtime/lib" \
    "$PACKAGE/runtime/libexec/wpe-webkit-2.0" "$PACKAGE/config" \
    "$PACKAGE/www" "$ROM/tools"
cp "$BASE/scripts/Install-Fire4Nix-Once.sh" "$PKG/Install.sh"
cp "$BASE/installer/Fire4Nix-Iniciar.sh" "$PACKAGE/Fire4Nix-Iniciar.sh"
cat > "$PACKAGE/bin/fire4nix-native-aarch64" <<'MOCK'
#!/bin/sh
[ "$1" = --check-platform ] || exit 127
# A matching ABI test must use only the selected private WPE runtime.
# The intentionally inherited foreign path must not contaminate preflight.
case "${LD_LIBRARY_PATH:-}" in
  "$FIRE4NIX_TEST_PACKAGE_LIB"|"$FIRE4NIX_TEST_INSTALLED_LIB") ;;
  *) printf 'Unexpected loader contamination: %s\n' "${LD_LIBRARY_PATH:-}" >&2; exit 94 ;;
esac
exit 0
MOCK
chmod +x "$PACKAGE/bin/fire4nix-native-aarch64"
cat > "$PACKAGE/Fire4Nix.sh" <<'MOCK'
#!/bin/sh
exit 0
MOCK
printf 'config\n' > "$PACKAGE/config/fire4nix.gptk"
printf '<!doctype html><title>mock</title>\n' > "$PACKAGE/www/inicio.html"
printf 'diagnostic\n' > "$PACKAGE/Diagnosticar-Fire4Nix.sh"
cp "$PACKAGE/Diagnosticar-Fire4Nix.sh" "$PKG/Diagnosticar-Fire4Nix.sh"
PKG_RUNTIME="$PACKAGE/runtime"
PKG_CHILD="$PKG_RUNTIME/libexec/wpe-webkit-2.0"
printf 'dummy engine\n' > "$PKG_RUNTIME/lib/libWPEWebKit-2.0.so.1"
for name in WPEWebProcess WPENetworkProcess; do
    printf 'process-%s\n' "$name" > "$PKG_CHILD/$name"
done
printf 'GPU_PROCESS_PROFILE=disabled_verified_wayland\n' > "$PKG_RUNTIME/BUILD-REPORT.txt"
install_once() {
    FIRE4NIX_ROMS="$ROM" FIRE4NIX_GAMEPAD=0 \
      FIRE4NIX_TEST_PACKAGE_LIB="$PKG_RUNTIME/lib" \
      FIRE4NIX_TEST_INSTALLED_LIB="$ROM/ports/fire4nix-completo/runtime/lib" \
      LD_LIBRARY_PATH="$T/incompatible-foreign-runtime" \
      sh "$PKG/Install.sh" > "$T/install.log" 2>&1
}
install_once
DEST="$ROM/ports/fire4nix-completo"
grep -Fxq 'GPU_PROCESS_PROFILE=disabled_verified_wayland' "$DEST/runtime/BUILD-REPORT.txt"
test ! -e "$DEST/runtime/libexec/wpe-webkit-2.0/WPEGPUProcess"
test -f "$ROM/ports/Fire4Nix.sh"
install_once
grep -Fq 'already installed and API-compatible' "$T/install.log"

# A contradictory report or a symlink must not replace a valid install.
old_content=$(cat "$DEST/runtime/BUILD-REPORT.txt")
printf 'GPU_PROCESS_PROFILE=disabled_verified_wayland\nGPU_PROCESS_PROFILE=required_unverified\n' > "$PKG_RUNTIME/BUILD-REPORT.txt"
set +e
install_once
rc=$?
set -e
test "$rc" -eq 5 || { echo "Invalid profile installer returned $rc" >&2; cat "$T/install.log"; exit 1; }
test "$(cat "$DEST/runtime/BUILD-REPORT.txt")" = "$old_content"
rm "$PKG_RUNTIME/BUILD-REPORT.txt"
printf 'GPU_PROCESS_PROFILE=disabled_verified_wayland\n' > "$T/foreign-report"
ln -s "$T/foreign-report" "$PKG_RUNTIME/BUILD-REPORT.txt"
set +e
install_once
rc=$?
set -e
test "$rc" -eq 5
test "$(cat "$DEST/runtime/BUILD-REPORT.txt")" = "$old_content"
rm "$PKG_RUNTIME/BUILD-REPORT.txt"

# Transition to GPU-on must install GPUProcess, not skip the update because
# Web/Network binaries and the engine library happen to have the same hashes.
printf 'GPU_PROCESS_PROFILE=enabled_verified\n' > "$PKG_RUNTIME/BUILD-REPORT.txt"
printf 'gpu-process\n' > "$PKG_CHILD/WPEGPUProcess"
install_once
grep -Fxq 'GPU_PROCESS_PROFILE=enabled_verified' "$DEST/runtime/BUILD-REPORT.txt"
test -s "$DEST/runtime/libexec/wpe-webkit-2.0/WPEGPUProcess"
install_once
grep -Fq 'already installed and API-compatible' "$T/install.log"

# Missing profile is a legacy three-process runtime: still valid with GPU.
rm "$PKG_RUNTIME/BUILD-REPORT.txt"
install_once
test ! -e "$DEST/runtime/BUILD-REPORT.txt"
install_once
grep -Fq 'already installed and API-compatible' "$T/install.log"

# A legacy build WITHOUT GPU is rejected; no existing installation changed.
rm "$PKG_CHILD/WPEGPUProcess"
set +e
install_once
rc=$?
set -e
test "$rc" -eq 5
test -s "$DEST/runtime/libexec/wpe-webkit-2.0/WPEGPUProcess"
echo 'R36H_PORTS_INSTALL_GPU_PROFILE=PASS_HOST_ONLY_ISOLATED_PRECHECK_NO_WEBKIT_LOADED'
