#!/bin/sh
# Non-hardware regression for isolated library loading and offline 139 tracing.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P) || exit 2
T=$(mktemp -d)
trap 'rm -rf "$T"' 0
APP="$T/my Fire4Nix"
mkdir -p "$APP/bin" "$APP/runtime/lib" "$APP/runtime/libexec/wpe-webkit-2.0" "$T/logs" "$T/reports" "$T/foreign"
cp "$HERE/installer/Fire4Nix-Iniciar.sh" "$APP/Fire4Nix-Iniciar.sh"
printf 'mock webkit\n' > "$APP/runtime/lib/libWPEWebKit-2.0.so.1"
printf 'mock EGL\n' > "$APP/runtime/lib/libEGL.so.1"
for p in WPEWebProcess WPENetworkProcess WPEGPUProcess; do
  printf 'mock process\n' > "$APP/runtime/libexec/wpe-webkit-2.0/$p"
done
cat > "$APP/bin/fire4nix-native-aarch64" <<'MOCK'
#!/bin/sh
printf 'observed_lib_path=%s\n' "$LD_LIBRARY_PATH" >> "$MOCK_RESULT"
printf 'observed_debug=%s\n' "${LD_DEBUG:-}" >> "$MOCK_RESULT"
printf 'observed_debug_output=%s\n' "${LD_DEBUG_OUTPUT:-}" >> "$MOCK_RESULT"
printf '[FIRE4NIX-NATIVE] dlopen libWPEWebKit-2.0.so.1\n'
printf '[FIRE4NIX-NATIVE] dlopen success\n'
printf '[FIRE4NIX-ABI] wpe_version=2.54.1\n'
exit 139
MOCK
chmod +x "$APP/bin/fire4nix-native-aarch64"
: > "$T/observed"
set +e
MOCK_RESULT="$T/observed" LD_LIBRARY_PATH="$T/foreign" FIRE4NIX_GAMEPAD=0 \
  FIRE4NIX_LOG_DIR="$T/logs" sh "$APP/Fire4Nix-Iniciar.sh" --check-platform >/dev/null
status=$?
set -e
test "$status" -eq 139
grep -Fxq "observed_lib_path=$APP/runtime/lib" "$T/observed"
grep -q 'library_path_mode=isolated_discarded_inherited_paths' "$T/logs/"*.log
grep -q 'warning=private_system_or_gpu_library:libEGL.so.1' "$T/logs/"*.log
if grep -q 'observed_lib_path=.*foreign' "$T/observed"; then
  echo 'FAIL: inherited foreign runtime leaked into isolated mode' >&2; exit 1
fi
: > "$T/observed"
set +e
MOCK_RESULT="$T/observed" LD_LIBRARY_PATH="$T/foreign" FIRE4NIX_INHERIT_LIBRARY_PATH=1 \
  FIRE4NIX_GAMEPAD=0 FIRE4NIX_LOG_DIR="$T/logs" \
  sh "$APP/Fire4Nix-Iniciar.sh" --check-platform >/dev/null
status=$?
set -e
test "$status" -eq 139
grep -Fxq "observed_lib_path=$APP/runtime/lib:$T/foreign" "$T/observed"
grep -q 'library_path_mode=compat_inherited' "$T/logs/"*.log
: > "$T/observed"
# Two separate probes must never share a loader debug output prefix.
for invocation in 1 2; do
  : > "$T/observed"
  set +e
  MOCK_RESULT="$T/observed" FIRE4NIX_LOADER_DEBUG=1 FIRE4NIX_GAMEPAD=0 \
    FIRE4NIX_LOG_DIR="$T/logs" sh "$APP/Fire4Nix-Iniciar.sh" --check-library >/dev/null 2>&1
  status=$?
  set -e
  test "$status" -eq 139
  trace=$(sed -n 's/^observed_debug_output=//p' "$T/observed" | tail -n 1)
  printf '%s\n' "$trace" | grep -Eq "^$T/logs/Fire4Nix-LD-[0-9]{8}-[0-9]{6}-[0-9]+$" || {
    echo "FAIL: loader debug trace prefix lacks process ID: $trace" >&2; exit 1;
  }
  if [ "$invocation" -eq 1 ]; then
    first_trace=$trace
  else
    test "$first_trace" != "$trace" || {
      echo 'FAIL: consecutive loader traces overwrite the same prefix' >&2; exit 1;
    }
  fi
done
: > "$T/observed"
FIRE4NIX_ROOT="$APP" FIRE4NIX_INVEST_REPORT_DIR="$T/reports" \
  sh "$HERE/installer/Fire4Nix-Investigar-139.sh" --safe > "$T/safe.txt"
test ! -s "$T/observed"
grep -q 'native_preflight=NOT_RUN_SAFE_MODE' "$T/safe.txt"
cat > "$APP/Fire4Nix-Iniciar.sh" <<'OUTDATED'
#!/bin/sh
echo 'outdated-launcher-was-invoked' >&2
exit 88
OUTDATED
# The standalone collector must bypass outdated SD launchers.
set +e
MOCK_RESULT="$T/observed" FIRE4NIX_ROOT="$APP" \
  FIRE4NIX_INVEST_REPORT_DIR="$T/reports" \
  sh "$HERE/installer/Fire4Nix-Investigar-139.sh" --trace > "$T/trace.txt"
status=$?
set -e
test "$status" -eq 0
grep -q '^native_preflight_exit=139' "$T/trace.txt"
grep -q '^crash_boundary=after_dlopen$' "$T/trace.txt"
grep -q '^loader_last_relevant_lines_begin$' "$T/trace.txt"
grep -q '^hardware_browser_rendering=NOT_VERIFIED$' "$T/trace.txt"
grep -Fxq "observed_lib_path=$APP/runtime/lib" "$T/observed"
if grep -q 'outdated-launcher-was-invoked' "$T/trace.txt"; then echo 'FAIL: tracer used legacy launcher' >&2; exit 1; fi
if grep -q '^native_preflight_exit=' "$T/safe.txt"; then
  echo 'FAIL: safe mode loaded a mocked native executable' >&2; exit 1
fi
# Simulate real dual-SD layout: ELF in Ports, 174MB runtime under tools.
mkdir -p "$T/remote-tools"
mv "$APP/runtime" "$T/remote-tools/runtime"
: > "$T/observed"
MOCK_RESULT="$T/observed" FIRE4NIX_BINARY_ROOT="$APP" \
  FIRE4NIX_RUNTIME_ROOT="$T/remote-tools" \
  FIRE4NIX_INVEST_REPORT_DIR="$T/reports" \
  sh "$HERE/installer/Fire4Nix-Investigar-139.sh" --safe > "$T/split-safe.txt"
grep -Fxq "installed_root=$APP" "$T/split-safe.txt"
grep -Fxq "wpe_runtime_root=$T/remote-tools" "$T/split-safe.txt"
grep -q "native_preflight=NOT_RUN_SAFE_MODE" "$T/split-safe.txt"
test ! -s "$T/observed"
MOCK_RESULT="$T/observed" FIRE4NIX_BINARY_ROOT="$APP" \
  FIRE4NIX_RUNTIME_ROOT="$T/remote-tools" \
  FIRE4NIX_INVEST_REPORT_DIR="$T/reports" \
  sh "$HERE/installer/Fire4Nix-Investigar-139.sh" --trace > "$T/split-trace.txt"
grep -Fxq "observed_lib_path=$T/remote-tools/runtime/lib" "$T/observed"
grep -q "^native_preflight_exit=139$" "$T/split-trace.txt"
grep -q "^crash_boundary=after_dlopen$" "$T/split-trace.txt"
grep -Fxq "selected_runtime=$T/remote-tools" "$T/split-trace.txt"
if grep -q "outdated-launcher-was-invoked" "$T/split-trace.txt"; then exit 1; fi
echo 'PASS: isolated/compat library path, unique loader traces, split native/runtime, no firmware edits, offline reports'
