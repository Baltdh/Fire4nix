#!/usr/bin/env bash
# Exercise the real WPEPlatform Wayland backend against a local headless
# Weston compositor. This proves compositor connection/surface creation and
# WebKit page execution, but not Mali hardware acceleration or an R36H frame.
set -euo pipefail

binary=${1:?usage: test_wayland_compositor_integration.sh NATIVE_BINARY HTML_FIXTURE WORK_DIR}
fixture=${2:?missing HTML fixture}
work=${3:?missing work directory}
for file in "$binary" "$fixture"; do
  [[ -s "$file" ]] || { echo "missing input: $file" >&2; exit 2; }
done
command -v weston >/dev/null
command -v timeout >/dev/null
command -v readelf >/dev/null
readelf -h "$binary" | grep -Eq 'Machine:.*AArch64' || {
  echo 'WAYLAND_WPE_TEST=FAIL_NON_AARCH64_BINARY' >&2; exit 3;
}

mkdir -p "$work/runtime" "$work/home" "$work/cache" "$work/data" "$work/logs"
chmod 700 "$work/runtime"
export XDG_RUNTIME_DIR="$work/runtime"
export WAYLAND_DISPLAY=wayland-fire4nix
export WESTON_LOG="$work/logs/weston.log"
export LIBGL_ALWAYS_SOFTWARE=1
unset WPE_DISPLAY MALI_DEFAULT_DISPLAY

weston --backend=headless-backend.so --renderer=pixman \
  --socket="$WAYLAND_DISPLAY" --idle-time=0 --width=640 --height=480 \
  --no-config --log="$WESTON_LOG" >"$work/logs/weston-stdout.log" 2>&1 &
weston_pid=$!
cleanup() {
  kill "$weston_pid" 2>/dev/null || true
  wait "$weston_pid" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

ready=0
for _ in $(seq 1 100); do
  if [[ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]]; then
    ready=1
    break
  fi
  if ! kill -0 "$weston_pid" 2>/dev/null; then
    cat "$work/logs/weston-stdout.log" "$WESTON_LOG" 2>/dev/null || true
    echo 'WAYLAND_WPE_TEST=FAIL_WESTON_EXITED_BEFORE_SOCKET' >&2
    exit 4
  fi
  sleep 0.1
done
[[ "$ready" -eq 1 ]] || {
  cat "$work/logs/weston-stdout.log" "$WESTON_LOG" 2>/dev/null || true
  echo 'WAYLAND_WPE_TEST=FAIL_WESTON_SOCKET_TIMEOUT' >&2
  exit 5
}

web_process="$(find /usr -type f -name WPEWebProcess -print -quit)"
[[ -n "$web_process" && -x "$web_process" ]] || {
  echo 'WAYLAND_WPE_TEST=FAIL_WPEWEBPROCESS_MISSING' >&2; exit 6;
}
webkit_exec_path="$(dirname "$web_process")"
[[ -x "$webkit_exec_path/WPENetworkProcess" ]] || {
  echo 'WAYLAND_WPE_TEST=FAIL_WPENETWORKPROCESS_MISSING' >&2; exit 7;
}

page="file://$fixture"
set +e
env WPE_PLATFORM=wayland \
  WEBKIT_EXEC_PATH="$webkit_exec_path" \
  WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1 \
  FIRE4NIX_LOW_MEMORY=1 \
  HOME="$work/home" \
  XDG_DATA_HOME="$work/data" \
  XDG_CACHE_HOME="$work/cache" \
  timeout --signal=TERM --kill-after=5s 90s \
  "$binary" --verify-offline "$page" \
  >"$work/logs/wpe-wayland.log" 2>&1
rc=$?
set -e
cat "$work/logs/wpe-wayland.log"
cat "$WESTON_LOG" >> "$work/logs/weston-combined.log"

if [[ "$rc" -ne 0 ]]; then
  echo "WAYLAND_WPE_TEST=FAIL_EXIT_$rc" | tee -a "$GITHUB_STEP_SUMMARY"
  exit "$rc"
fi
for marker in \
  'WPEPlatform WPEView available' \
  'WPEPlatform display disconnect monitoring active' \
  '[FIRE4NIX-VERIFY] offline_dom=PASS' \
  '[FIRE4NIX-VERIFY] inline_javascript=PASS' \
  '[FIRE4NIX-VERIFY] computed_css=PASS' \
  '[FIRE4NIX-VERIFY] button_event=PASS'; do
  grep -Fq "$marker" "$work/logs/wpe-wayland.log" || {
    echo "WAYLAND_WPE_TEST=FAIL_MISSING_MARKER:$marker" | tee -a "$GITHUB_STEP_SUMMARY"
    exit 8
  }
done
if grep -Fq 'WPE display disconnected' "$work/logs/wpe-wayland.log"; then
  echo 'WAYLAND_WPE_TEST=FAIL_DISPLAY_DISCONNECTED' | tee -a "$GITHUB_STEP_SUMMARY"
  exit 9
fi
echo 'WAYLAND_WPE_TEST=PASS_REAL_WPE_WAYLAND_BACKEND_WESTON_PIXMAN_ARM64' | tee -a "$GITHUB_STEP_SUMMARY"
echo 'WAYLAND_WPE_COMPOSITOR_CONNECTION=PASS' | tee -a "$GITHUB_STEP_SUMMARY"
echo 'WAYLAND_WPE_VIEW_CREATED=PASS' | tee -a "$GITHUB_STEP_SUMMARY"
echo 'WAYLAND_WPE_PAGE_DOM_JS_CSS_CLICK=PASS' | tee -a "$GITHUB_STEP_SUMMARY"
echo 'WAYLAND_WPE_MALI_HARDWARE_VERIFIED=no' | tee -a "$GITHUB_STEP_SUMMARY"
echo 'WAYLAND_WPE_R36H_FRAME_VERIFIED=no' | tee -a "$GITHUB_STEP_SUMMARY"
