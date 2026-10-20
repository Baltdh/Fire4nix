#!/bin/sh
# Verifies controller helper lifecycle WITHOUT a physical RK3326 or real gptokeyb.
set -eu
source_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
T=$(mktemp -d)
socket_pid=""
cleanup() {
  [ -z "$socket_pid" ] || kill "$socket_pid" 2>/dev/null || true
  rm -rf "$T"
}
trap cleanup EXIT HUP INT TERM
mkdir -p "$T/install/bin" "$T/install/config" "$T/install/runtime/libexec/wpe-webkit-2.0" "$T/install/runtime/lib" "$T/logs"
mkdir -p "$T/install/www"
cp "$source_dir/installer/www/primeiro-teste-r36h.html" "$T/install/www/primeiro-teste-r36h.html"
cp "$source_dir/installer/Fire4Nix-Iniciar.sh" "$T/install/Fire4Nix-Iniciar.sh"
cp "$source_dir/installer/config/fire4nix.gptk" "$T/install/config/fire4nix.gptk"
# CI runs on an ARM64 host; compile a real ELF shared-object header for
# the launcher guard. It is a mock and cannot browse webpages.
printf 'void mock_webkit_symbol(void) {}\n' |
  cc -x c -shared -fPIC -o "$T/install/runtime/lib/libWPEWebKit-2.0.so.1" -
for part in WPEWebProcess WPENetworkProcess WPEGPUProcess; do
  printf 'stub-child' > "$T/install/runtime/libexec/wpe-webkit-2.0/$part"
done
cat > "$T/install/bin/fire4nix-native-aarch64" <<'BROWSER'
#!/bin/sh
printf 'browser_start\n' >> "$FIRE4NIX_TEST_LOG"
printf 'browser_url=%s\n' "${1:-none}" >> "$FIRE4NIX_TEST_LOG"
printf 'gpu_afbc=%s\n' "${MALI_WAYLAND_AFBC:-unset}" >> "$FIRE4NIX_TEST_LOG"
sleep 1
printf 'browser_exit\n' >> "$FIRE4NIX_TEST_LOG"
exit 0
BROWSER
chmod +x "$T/install/bin/fire4nix-native-aarch64"
cat > "$T/gptokeyb" <<'GAMEPAD'
#!/bin/sh
printf 'gamepad_started:%s\n' "$*" >> "$FIRE4NIX_TEST_LOG"
trap 'printf "gamepad_stopped\n" >> "$FIRE4NIX_TEST_LOG"; exit 0' TERM
while :; do sleep 1; done
GAMEPAD
chmod +x "$T/gptokeyb"

# A socket is checked by the launcher; a test stub suffices because the browser is mocked.
python3 -c 'import socket,sys,time; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1]); s.listen(1); time.sleep(45)' "$T/wayland-test" &
socket_pid=$!
i=0
while [ ! -S "$T/wayland-test" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
test -S "$T/wayland-test"

: > "$T/actions"
env XDG_RUNTIME_DIR="$T" WAYLAND_DISPLAY=wayland-test \
    FIRE4NIX_GPTOKEYB="$T/gptokeyb" FIRE4NIX_TEST_LOG="$T/actions" \
    FIRE4NIX_LOG_DIR="$T/logs" FIRE4NIX_GAMEPAD=1 \
    sh "$T/install/Fire4Nix-Iniciar.sh" --open >/dev/null
grep -q 'gamepad_started:-c .*fire4nix.gptk' "$T/actions"
grep -q 'browser_exit' "$T/actions"
grep -q 'gamepad_stopped' "$T/actions"
grep -q 'gamepad=running pid=' "$T/logs"/Fire4Nix-*
grep -q 'fire4nix_exit_code=0' "$T/logs"/Fire4Nix-*

: > "$T/actions"
env XDG_RUNTIME_DIR="$T" WAYLAND_DISPLAY=wayland-test \
    FIRE4NIX_GPTOKEYB="$T/gptokeyb" FIRE4NIX_TEST_LOG="$T/actions" \
    FIRE4NIX_LOG_DIR="$T/logs" FIRE4NIX_GAMEPAD=0 \
    sh "$T/install/Fire4Nix-Iniciar.sh" --open >/dev/null
if grep -q 'gamepad_started' "$T/actions"; then echo "disabled gamepad incorrectly started" >&2; exit 1; fi
grep -q 'browser_exit' "$T/actions"

# Respect native ROCKNIX GPU policy and preserve explicit user override.
: > "$T/actions"
env -u MALI_WAYLAND_AFBC XDG_RUNTIME_DIR="$T" WAYLAND_DISPLAY=wayland-test \
  FIRE4NIX_GPTOKEYB="$T/gptokeyb" FIRE4NIX_TEST_LOG="$T/actions" \
  FIRE4NIX_LOG_DIR="$T/logs" FIRE4NIX_GAMEPAD=0 \
  sh "$T/install/Fire4Nix-Iniciar.sh" --open >/dev/null
grep -q '^gpu_afbc=unset$' "$T/actions"
: > "$T/actions"
env MALI_WAYLAND_AFBC=1 XDG_RUNTIME_DIR="$T" WAYLAND_DISPLAY=wayland-test \
  FIRE4NIX_GPTOKEYB="$T/gptokeyb" FIRE4NIX_TEST_LOG="$T/actions" \
  FIRE4NIX_LOG_DIR="$T/logs" FIRE4NIX_GAMEPAD=0 \
  sh "$T/install/Fire4Nix-Iniciar.sh" --open >/dev/null
grep -q '^gpu_afbc=1$' "$T/actions"
# Preflights should never start gptokeyb.
: > "$T/actions"
env XDG_RUNTIME_DIR="$T" WAYLAND_DISPLAY=wayland-test \
    FIRE4NIX_GPTOKEYB="$T/gptokeyb" FIRE4NIX_TEST_LOG="$T/actions" \
    FIRE4NIX_LOG_DIR="$T/logs" FIRE4NIX_GAMEPAD=1 \
    sh "$T/install/Fire4Nix-Iniciar.sh" --check-platform >/dev/null
if grep -q 'gamepad_started' "$T/actions"; then echo "preflight started gamepad" >&2; exit 1; fi
# A broken gptokeyb must be reported rather than logged as running.
cat > "$T/failing-gptokeyb" <<'BROKEN'
#!/bin/sh
exit 42
BROKEN
chmod +x "$T/failing-gptokeyb"
: > "$T/actions"
env XDG_RUNTIME_DIR="$T" WAYLAND_DISPLAY=wayland-test \
    FIRE4NIX_GPTOKEYB="$T/failing-gptokeyb" FIRE4NIX_TEST_LOG="$T/actions" \
    FIRE4NIX_LOG_DIR="$T/logs" FIRE4NIX_GAMEPAD=1 \
    sh "$T/install/Fire4Nix-Iniciar.sh" --open >/dev/null
grep -q 'browser_exit' "$T/actions"
grep -q 'gamepad=helper_exited_early exit_code=42' "$T/logs"/Fire4Nix-*

# Two launches within the same second may not share a diagnostic filename.
before=$(find "$T/logs" -type f -name 'Fire4Nix-*' | wc -l)
env XDG_RUNTIME_DIR="$T" WAYLAND_DISPLAY=wayland-test \
    FIRE4NIX_GPTOKEYB="$T/gptokeyb" FIRE4NIX_TEST_LOG="$T/actions" \
    FIRE4NIX_LOG_DIR="$T/logs" FIRE4NIX_GAMEPAD=0 \
    sh "$T/install/Fire4Nix-Iniciar.sh" --check-platform >/dev/null
env XDG_RUNTIME_DIR="$T" WAYLAND_DISPLAY=wayland-test \
    FIRE4NIX_GPTOKEYB="$T/gptokeyb" FIRE4NIX_TEST_LOG="$T/actions" \
    FIRE4NIX_LOG_DIR="$T/logs" FIRE4NIX_GAMEPAD=0 \
    sh "$T/install/Fire4Nix-Iniciar.sh" --check-platform >/dev/null
after=$(find "$T/logs" -type f -name 'Fire4Nix-*' | wc -l)
test "$after" -eq "$((before + 2))"
# Real 2026-10-20 R36H finding: exactly 174006016 bytes can still be invalid.
# Reject invalid ELF before executing the native launcher or starting gamepad.
GOOD_WPE="$T/good-webkit.so"
cp "$T/install/runtime/lib/libWPEWebKit-2.0.so.1" "$GOOD_WPE"
printf 'not-an-ELF\n' > "$T/install/runtime/lib/libWPEWebKit-2.0.so.1"
: > "$T/actions"
set +e
env XDG_RUNTIME_DIR="$T" WAYLAND_DISPLAY=wayland-test \
  FIRE4NIX_GPTOKEYB="$T/gptokeyb" FIRE4NIX_TEST_LOG="$T/actions" \
  FIRE4NIX_LOG_DIR="$T/logs" FIRE4NIX_GAMEPAD=1 \
  sh "$T/install/Fire4Nix-Iniciar.sh" --open > "$T/invalid-elf.log" 2>&1
blocked=$?
set -e
test "$blocked" -eq 65
grep -q 'runtime_elf_status=INVALID_OR_NOT_AARCH64' "$T/invalid-elf.log"
if grep -q 'browser_start\|gamepad_started' "$T/actions"; then
  echo 'FAIL: attempted to launch corrupted WebKit' >&2; exit 1
fi
cp "$GOOD_WPE" "$T/install/runtime/lib/libWPEWebKit-2.0.so.1"
# Guard the known real GST_CAT_DEFAULT undefined reference in libgstvideo.
printf 'extern void *GST_CAT_DEFAULT;\nvoid *gst_mock(void) { return GST_CAT_DEFAULT; }\n' |
  cc -x c -shared -fPIC -o "$T/install/runtime/lib/libgstvideo-1.0.so.0" -
: > "$T/actions"
set +e
env XDG_RUNTIME_DIR="$T" WAYLAND_DISPLAY=wayland-test \
  FIRE4NIX_GPTOKEYB="$T/gptokeyb" FIRE4NIX_TEST_LOG="$T/actions" \
  FIRE4NIX_LOG_DIR="$T/logs" FIRE4NIX_GAMEPAD=1 \
  sh "$T/install/Fire4Nix-Iniciar.sh" --open > "$T/gst-block.log" 2>&1
blocked=$?
set -e
test "$blocked" -eq 65
grep -q 'runtime_gstreamer_status=BLOCKED_GST_CAT_DEFAULT' "$T/gst-block.log"
test ! -s "$T/actions"
# Fixed local first-test mode must use only a packaged offline file:// URL.
rm -f "$T/install/runtime/lib/libgstvideo-1.0.so.0"
: > "$T/actions"
env XDG_RUNTIME_DIR="$T" WAYLAND_DISPLAY=wayland-test \
  FIRE4NIX_GPTOKEYB="$T/gptokeyb" FIRE4NIX_TEST_LOG="$T/actions" \
  FIRE4NIX_LOG_DIR="$T/logs" FIRE4NIX_GAMEPAD=0 \
  sh "$T/install/Fire4Nix-Iniciar.sh" --first-offline-test >/dev/null
grep -Fxq "browser_url=file://$T/install/www/primeiro-teste-r36h.html" "$T/actions"
# Explicitly prevent a remote URL from being injected into the offline mode.
: > "$T/actions"
set +e
env XDG_RUNTIME_DIR="$T" WAYLAND_DISPLAY=wayland-test \
  FIRE4NIX_GPTOKEYB="$T/gptokeyb" FIRE4NIX_TEST_LOG="$T/actions" \
  FIRE4NIX_LOG_DIR="$T/logs" FIRE4NIX_GAMEPAD=0 \
  sh "$T/install/Fire4Nix-Iniciar.sh" --first-offline-test https://example.invalid \
  > "$T/blocked-remote.log" 2>&1
rc=$?
set -e
test "$rc" -eq 2
test ! -s "$T/actions"
# Missing offline fixture must fail closed before launching any executable.
mv "$T/install/www/primeiro-teste-r36h.html" "$T/fixture-hidden"
: > "$T/actions"
set +e
env XDG_RUNTIME_DIR="$T" WAYLAND_DISPLAY=wayland-test \
  FIRE4NIX_GPTOKEYB="$T/gptokeyb" FIRE4NIX_TEST_LOG="$T/actions" \
  FIRE4NIX_LOG_DIR="$T/logs" FIRE4NIX_GAMEPAD=1 \
  sh "$T/install/Fire4Nix-Iniciar.sh" --first-offline-test \
  > "$T/missing-offline.log" 2>&1
rc=$?
set -e
test "$rc" -eq 66
test ! -s "$T/actions"
echo "PASS: gamepad lifecycle, failure detection, preflights, unique diagnostics and opt-out"
