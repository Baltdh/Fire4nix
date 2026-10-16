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
cp "$source_dir/installer/Fire4Nix-Iniciar.sh" "$T/install/Fire4Nix-Iniciar.sh"
cp "$source_dir/installer/config/fire4nix.gptk" "$T/install/config/fire4nix.gptk"
printf 'stub-wpe' > "$T/install/runtime/lib/libWPEWebKit-2.0.so.1"
for part in WPEWebProcess WPENetworkProcess WPEGPUProcess; do
  printf 'stub-child' > "$T/install/runtime/libexec/wpe-webkit-2.0/$part"
done
cat > "$T/install/bin/fire4nix-native-aarch64" <<'BROWSER'
#!/bin/sh
printf 'browser_start\n' >> "$FIRE4NIX_TEST_LOG"
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
python3 -c 'import socket,sys,time; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1]); s.listen(1); time.sleep(12)' "$T/wayland-test" &
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
grep -q 'gamepad=started pid=' "$T/logs/"*.log
grep -q 'fire4nix_exit_code=0' "$T/logs/"*.log

: > "$T/actions"
env XDG_RUNTIME_DIR="$T" WAYLAND_DISPLAY=wayland-test \
    FIRE4NIX_GPTOKEYB="$T/gptokeyb" FIRE4NIX_TEST_LOG="$T/actions" \
    FIRE4NIX_LOG_DIR="$T/logs" FIRE4NIX_GAMEPAD=0 \
    sh "$T/install/Fire4Nix-Iniciar.sh" --open >/dev/null
if grep -q 'gamepad_started' "$T/actions"; then echo "disabled gamepad incorrectly started" >&2; exit 1; fi
grep -q 'browser_exit' "$T/actions"

# Preflights should never start gptokeyb.
: > "$T/actions"
env XDG_RUNTIME_DIR="$T" WAYLAND_DISPLAY=wayland-test \
    FIRE4NIX_GPTOKEYB="$T/gptokeyb" FIRE4NIX_TEST_LOG="$T/actions" \
    FIRE4NIX_LOG_DIR="$T/logs" FIRE4NIX_GAMEPAD=1 \
    sh "$T/install/Fire4Nix-Iniciar.sh" --check-platform >/dev/null
if grep -q 'gamepad_started' "$T/actions"; then echo "preflight started gamepad" >&2; exit 1; fi
echo "PASS: controller adapter starts for interactive launch, exits with browser, respects disable mode and preflight"
