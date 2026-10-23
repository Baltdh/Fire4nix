#!/usr/bin/env bash
# Host-only read-only target validation; no WebKit build or hardware required.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd -P)
script="$root/scripts/build-wpe2541-subprocesses-rocknix.sh"
temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT
mkdir -p "$temp/configure" "$temp/report"
cat > "$temp/configure/build.ninja" <<'EOF'
build WebKit: phony
build WebProcess: phony
build NetworkProcess: phony
build WPEInjectedBundle: phony
build InspectorResources: phony
EOF
cat > "$temp/configure/CMakeCache.txt" <<'EOF'
ENABLE_WPE_PLATFORM_WAYLAND:BOOL=ON
ENABLE_GPU_PROCESS:BOOL=OFF
USE_GSTREAMER:BOOL=OFF
USE_GBM:BOOL=OFF
USE_LIBDRM:BOOL=OFF
EOF
FIRE4NIX_WPE_BUILD_WORK="$temp" bash "$script" --check > "$temp/acceptance.txt"
grep -Fxq 'WPE_SUBPROCESS_TARGET_CHECK=PASS_STATIC' "$temp/acceptance.txt"
grep -Fxq 'WPE_REQUIRED_TARGETS=WebKit,WebProcess,NetworkProcess,WPEInjectedBundle,InspectorResources' "$temp/acceptance.txt"
grep -Fxq 'WPE_PROCESS_BINARIES_BUILT=no' "$temp/acceptance.txt"

# Reject a partial target Ninja graph.
sed -i '/^build NetworkProcess:/d' "$temp/configure/build.ninja"
if FIRE4NIX_WPE_BUILD_WORK="$temp" bash "$script" --check > /dev/null 2>&1; then
  echo 'FAIL: missing WPENetworkProcess target was accepted' >&2; exit 1
fi
echo 'build NetworkProcess: phony' >> "$temp/configure/build.ninja"
# WPEInjectedBundle is a separate module: WebProcess and NetworkProcess do
# not build it automatically. Missing module must fail prior to hours of CI.
sed -i '/^build WPEInjectedBundle:/d' "$temp/configure/build.ninja"
if FIRE4NIX_WPE_BUILD_WORK="$temp" bash "$script" --check > /dev/null 2>&1; then
  echo 'FAIL: missing separately installed WPEInjectedBundle accepted' >&2; exit 1
fi
echo 'build WPEInjectedBundle: phony' >> "$temp/configure/build.ninja"

# inspector.gresource is produced by the independent InspectorResources target.
sed -i '/^build InspectorResources:/d' "$temp/configure/build.ninja"
if FIRE4NIX_WPE_BUILD_WORK="$temp" bash "$script" --check > /dev/null 2>&1; then
  echo 'FAIL: missing InspectorResources target accepted' >&2; exit 1
fi
echo 'build InspectorResources: phony' >> "$temp/configure/build.ninja"

# Keep the real CI compilation list in sync with the four independent targets.
grep -Fq 'cmake --build "$build" --target WebProcess NetworkProcess WPEInjectedBundle InspectorResources --parallel 2' "$script"


# Reject GPU enabled (requires GPUProcess, not the two-helper configuration).
sed -i 's/ENABLE_GPU_PROCESS:BOOL=OFF/ENABLE_GPU_PROCESS:BOOL=ON/' "$temp/configure/CMakeCache.txt"
if FIRE4NIX_WPE_BUILD_WORK="$temp" bash "$script" --check > /dev/null 2>&1; then
  echo 'FAIL: GPU-on configuration accepted as GPU-off' >&2; exit 1
fi
sed -i 's/ENABLE_GPU_PROCESS:BOOL=ON/ENABLE_GPU_PROCESS:BOOL=OFF/' "$temp/configure/CMakeCache.txt"

# Reject media enabled despite nominal Wayland selection.
sed -i 's/USE_GSTREAMER:BOOL=OFF/USE_GSTREAMER:BOOL=ON/' "$temp/configure/CMakeCache.txt"
if FIRE4NIX_WPE_BUILD_WORK="$temp" bash "$script" --check > /dev/null 2>&1; then
  echo 'FAIL: GStreamer-on configuration accepted' >&2; exit 1
fi
sed -i 's/USE_GSTREAMER:BOOL=ON/USE_GSTREAMER:BOOL=OFF/' "$temp/configure/CMakeCache.txt"

# Prevent --build from becoming an implicit local compilation action.
if FIRE4NIX_WPE_BUILD_WORK="$temp" bash "$script" --build > /dev/null 2>&1; then
  echo 'FAIL: cross-build executed outside authenticated CI' >&2; exit 1
fi
# The CI-only script fails closed with no mode argument. Prevent the
# workflow from being silently wired to the invalid default again.
# This is a textual dispatch contract test, not a target compilation.
workflow="$root/.github/workflows/r36h-wpe2541-processes-real-rk3326.yml"
invocations=$(grep -F 'bash fire4nix/scripts/build-wpe2541-subprocesses-rocknix.sh' "$workflow")
expected='          bash fire4nix/scripts/build-wpe2541-subprocesses-rocknix.sh --build'
if [[ "$invocations" != "$expected" ]]; then
  echo 'FAIL: real WPE process workflow must explicitly pass --build exactly once' >&2
  printf 'found: %s\n' "$invocations" >&2
  exit 1
fi
# The target subprocess job is opt-in to avoid starting an hours-long
# ARM64 WebKit build through an unrelated host-only unit test.
grep -Fq '  workflow_dispatch:' "$workflow"
echo 'WPE_TWO_PROCESSES_WORKFLOW=PASS_EXPLICIT_BUILD_MODE'
echo 'WPE_TWO_PROCESSES_STATIC_GUARD=PASS_NO_TARGET_EXECUTION'
