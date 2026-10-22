#!/bin/sh
# Offline launcher regression for ROCKNIX GPU-off stage reports.
# The native executable is a harmless shell mock; WebKit is never loaded.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P) || exit 2
T=$(mktemp -d)
trap 'rm -rf "$T"' 0
APP="$T/Fire4Nix"
mkdir -p "$APP/bin" "$APP/runtime/lib" "$APP/runtime/libexec/wpe-webkit-2.0" "$T/logs"
cp "$ROOT/installer/Fire4Nix-Iniciar.sh" "$APP/Fire4Nix-Iniciar.sh"
cat > "$APP/bin/fire4nix-native-aarch64" <<'MOCK'
#!/bin/sh
echo "MOCK_NATIVE_CALLED=$*" >> "$FIRE4NIX_TEST_NATIVE_TRACE"
exit 0
MOCK
chmod +x "$APP/bin/fire4nix-native-aarch64"
printf 'placeholder WPE not loaded\n' > "$APP/runtime/lib/libWPEWebKit-2.0.so.1"
printf 'web\n' > "$APP/runtime/libexec/wpe-webkit-2.0/WPEWebProcess"
printf 'network\n' > "$APP/runtime/libexec/wpe-webkit-2.0/WPENetworkProcess"
export FIRE4NIX_TEST_NATIVE_TRACE="$T/native-call.txt"
LAUNCHER="$APP/Fire4Nix-Iniciar.sh"
run_ok() {
  FIRE4NIX_LOG_DIR="$T/logs" sh "$LAUNCHER" --check-platform > "$T/ok.log"
  grep -Fq 'MOCK_NATIVE_CALLED=' "$T/native-call.txt"
  rm -f "$T/native-call.txt"
}
run_fail() {
  expected=$1
  set +e
  FIRE4NIX_LOG_DIR="$T/logs" sh "$LAUNCHER" --check-platform > "$T/error.log" 2>&1
  rc=$?
  set -e
  test "$rc" -eq 127 || { echo "Wrong rejection status: $rc" >&2; exit 1; }
  grep -Fq "$expected" "$T/error.log"
  test ! -e "$T/native-call.txt"
}
# Old installations without a report must not silently omit GPUProcess.
run_fail 'Missing WebKit subprocess: WPEGPUProcess'
cat > "$APP/runtime/BUILD-REPORT.txt" <<'PROOF'
Fire4Nix WPE runtime staged from ROCKNIX SDK DESTDIR.
GPU_PROCESS_PROFILE=disabled_verified_wayland
Graphical startup and Mali/Wayland have NOT been tested here.
PROOF
run_ok
grep -Frq 'gpu_process_required=0' "$T/logs"
# Both Web and Network subprocesses remain mandatory in GPU-off mode.
rm "$APP/runtime/libexec/wpe-webkit-2.0/WPENetworkProcess"
run_fail 'Missing WebKit subprocess: WPENetworkProcess'
printf 'network\n' > "$APP/runtime/libexec/wpe-webkit-2.0/WPENetworkProcess"
# Unknown / contradictory profile text must not bypass the requirement.
printf 'GPU_PROCESS_PROFILE=disabled_verified_wayland\nGPU_PROCESS_PROFILE=enabled_verified\n' > "$APP/runtime/BUILD-REPORT.txt"
run_fail 'Invalid or conflicting WPE GPU process profile'
echo 'GPU_PROCESS_PROFILE=disabled' > "$APP/runtime/BUILD-REPORT.txt"
run_fail 'Invalid or conflicting WPE GPU process profile'
rm -f "$APP/runtime/BUILD-REPORT.txt"
# Verified GPU ON and old no-cache profile still require the helper.
for profile in enabled_verified required_unverified; do
  echo "GPU_PROCESS_PROFILE=$profile" > "$APP/runtime/BUILD-REPORT.txt"
  run_fail 'Missing WebKit subprocess: WPEGPUProcess'
done
printf 'gpu\n' > "$APP/runtime/libexec/wpe-webkit-2.0/WPEGPUProcess"
run_ok
grep -Frq 'gpu_process_required=1' "$T/logs"
# File symlink profiles are rejected instead of followed outside runtime.
rm "$APP/runtime/BUILD-REPORT.txt"
echo 'GPU_PROCESS_PROFILE=disabled_verified_wayland' > "$T/external-profile"
ln -s "$T/external-profile" "$APP/runtime/BUILD-REPORT.txt"
run_fail 'Invalid WPE runtime build report'
echo 'PASS: GPU-disabled launcher honors verified staged report and fails closed on legacy/invalid profiles (host mock)'
