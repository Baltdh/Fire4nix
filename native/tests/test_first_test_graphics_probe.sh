#!/bin/sh
# Host regression for the packaged R36H read-only EGL probe entry point.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P) || exit 2
T=$(mktemp -d)
trap 'rm -rf "$T"' 0
APP="$T/app"
FAKE="$T/fake-bin"
mkdir -p "$APP" "$FAKE"
cp "$ROOT/installer/Fire4Nix-Primeiro-Teste-R36.sh" "$APP/Fire4Nix-Primeiro-Teste-R36.sh"
cp "$ROOT/installer/Fire4Nix-EGL-R36H.py" "$APP/Fire4Nix-EGL-R36H.py"

cat > "$FAKE/uname" <<'MOCK'
#!/bin/sh
case "${1:-}" in
  -m) echo aarch64 ;;
  -r) echo mock-rocknix-kernel ;;
  *) echo aarch64 ;;
esac
MOCK
cat > "$FAKE/timeout" <<'MOCK'
#!/bin/sh
[ "${1:-}" = 15s ] || exit 98
shift
if [ "${FIRE4NIX_MOCK_TIMEOUT:-0}" = 1 ]; then
  echo 'MOCK_TIMEOUT=1'
  exit 124
fi
exec "$@"
MOCK
cat > "$FAKE/python3" <<'MOCK'
#!/bin/sh
[ -s "${1:-}" ] || exit 97
[ "${MALI_DEFAULT_DISPLAY:-}" = wayland ] || exit 96
echo 'MOCK_EGL_PROBE=EXECUTED'
exit "${FIRE4NIX_MOCK_EGL_EXIT:-0}"
MOCK
chmod +x "$FAKE/uname" "$FAKE/timeout" "$FAKE/python3"

PATH="$FAKE:$PATH" FIRE4NIX_TEST_REPORT_DIR="$T/pass" \
  sh "$APP/Fire4Nix-Primeiro-Teste-R36.sh" --graphics-probe > "$T/pass.out"
grep -Fq 'MOCK_EGL_PROBE=EXECUTED' "$T/pass/Primeiro-Teste-R36H-ULTIMO.txt"
grep -Fxq 'graphics_probe_exit=0' "$T/pass/Primeiro-Teste-R36H-ULTIMO.txt"
grep -Fxq 'EGL_PROBE=PASS_OFFSCREEN_CONTEXT_ONLY' "$T/pass/Primeiro-Teste-R36H-ULTIMO.txt"
grep -Fxq 'GRAPHICAL_FRAME_VERIFIED=no' "$T/pass/Primeiro-Teste-R36H-ULTIMO.txt"

set +e
PATH="$FAKE:$PATH" FIRE4NIX_MOCK_EGL_EXIT=6 FIRE4NIX_TEST_REPORT_DIR="$T/fail" \
  sh "$APP/Fire4Nix-Primeiro-Teste-R36.sh" --graphics-probe > "$T/fail.out" 2>&1
rc=$?
set -e
test "$rc" -eq 6
grep -Fxq 'graphics_probe_exit=6' "$T/fail/Primeiro-Teste-R36H-ULTIMO.txt"
grep -Fxq 'EGL_PROBE=GLES2_CONTEXT_SETUP_FAILED' "$T/fail/Primeiro-Teste-R36H-ULTIMO.txt"

set +e
PATH="$FAKE:$PATH" FIRE4NIX_MOCK_TIMEOUT=1 FIRE4NIX_TEST_REPORT_DIR="$T/timeout" \
  sh "$APP/Fire4Nix-Primeiro-Teste-R36.sh" --graphics-probe > "$T/timeout.out" 2>&1
rc=$?
set -e
test "$rc" -eq 124
grep -Fxq 'graphics_probe_exit=124' "$T/timeout/Primeiro-Teste-R36H-ULTIMO.txt"
grep -Fxq 'EGL_PROBE=TIMEOUT_OR_KILLED' "$T/timeout/Primeiro-Teste-R36H-ULTIMO.txt"

echo 'PASS: graphics probe mode is bounded, isolated, reports success/failure/timeout, and never claims a visible frame'
