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

weston --debug --backend=headless-backend.so --renderer=pixman \
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
# The DOM verifier above exits as soon as JavaScript checks pass. Start a
# separate interactive session and capture the actual Weston output so CI
# verifies pixels, not only DOM state or WPEView creation.
command -v weston-screenshooter >/dev/null || {
  echo 'WAYLAND_WPE_FRAME=FAIL_WESTON_SCREENSHOOTER_MISSING' | tee -a "$GITHUB_STEP_SUMMARY"
  exit 10
}
command -v python3 >/dev/null
visual_pid=
cleanup_visual() {
  if [[ -n "$visual_pid" ]]; then
    kill "$visual_pid" 2>/dev/null || true
    wait "$visual_pid" 2>/dev/null || true
    visual_pid=
  fi
}
trap 'cleanup_visual; cleanup' EXIT INT TERM

env WPE_PLATFORM=wayland \
  WEBKIT_EXEC_PATH="$webkit_exec_path" \
  WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1 \
  FIRE4NIX_LOW_MEMORY=1 \
  HOME="$work/home" \
  XDG_DATA_HOME="$work/data" \
  XDG_CACHE_HOME="$work/cache" \
  "$binary" --open "$page" >"$work/logs/wpe-wayland-visual.log" 2>&1 &
visual_pid=$!
loaded=0
for _ in $(seq 1 150); do
  if grep -Fq 'load-event=3' "$work/logs/wpe-wayland-visual.log" 2>/dev/null; then
    loaded=1
    break
  fi
  if ! kill -0 "$visual_pid" 2>/dev/null; then
    cat "$work/logs/wpe-wayland-visual.log"
    echo 'WAYLAND_WPE_FRAME=FAIL_BROWSER_EXITED_BEFORE_LOAD' | tee -a "$GITHUB_STEP_SUMMARY"
    exit 11
  fi
  sleep 0.1
done
[[ "$loaded" -eq 1 ]] || {
  cat "$work/logs/wpe-wayland-visual.log"
  echo 'WAYLAND_WPE_FRAME=FAIL_PAGE_LOAD_TIMEOUT' | tee -a "$GITHUB_STEP_SUMMARY"
  exit 12
}
sleep 1
set +e
(
  cd "$work"
  XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" WAYLAND_DISPLAY="$WAYLAND_DISPLAY" \
    timeout --signal=TERM --kill-after=3s 15s weston-screenshooter
) >"$work/logs/weston-screenshooter.log" 2>&1
capture_rc=$?
set -e
cat "$work/logs/weston-screenshooter.log"
[[ "$capture_rc" -eq 0 ]] || {
  echo "WAYLAND_WPE_FRAME=FAIL_SCREENSHOT_EXIT_$capture_rc" | tee -a "$GITHUB_STEP_SUMMARY"
  exit 13
}
screenshot=$(find "$work" -maxdepth 3 -type f -name '*.png' -print -quit)
[[ -n "$screenshot" && -s "$screenshot" ]] || {
  echo 'WAYLAND_WPE_FRAME=FAIL_SCREENSHOT_FILE_MISSING' | tee -a "$GITHUB_STEP_SUMMARY"
  exit 14
}
python3 - "$screenshot" <<'PY'
from collections import Counter
from pathlib import Path
import sys
from PIL import Image

path = Path(sys.argv[1])
image = Image.open(path).convert("RGB")
if image.size != (640, 480):
    raise SystemExit(f"WAYLAND_WPE_FRAME=FAIL_DIMENSIONS_{image.width}x{image.height}")
counts = Counter(image.getdata())
targets = {
    "blue_swatch": (0x37, 0x73, 0xB8),
    "orange_swatch": (0xDA, 0x77, 0x4E),
    "green_swatch": (0x68, 0xA6, 0x70),
    "page_background": (0x10, 0x18, 0x27),
}
for name, rgb in targets.items():
    pixels = counts[rgb]
    print(f"WAYLAND_FRAME_PIXEL_{name}={pixels}")
    if pixels < 300:
        raise SystemExit(f"WAYLAND_WPE_FRAME=FAIL_MISSING_{name}_PIXELS")
print(f"WAYLAND_WPE_FRAME=PASS_PIXELS_640x480 screenshot={path}")
PY
cleanup_visual
cat "$work/logs/wpe-wayland-visual.log"
echo 'WAYLAND_WPE_FRAME=PASS_WESTON_CAPTURED_RENDERED_PIXELS_640X480' | tee -a "$GITHUB_STEP_SUMMARY"
