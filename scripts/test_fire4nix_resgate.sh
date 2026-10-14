#!/bin/sh
# Linux-hosted MOCK test of launcher control flow, NOT native ARM64 graphical validation.
set -eu
SCRIPT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/Fire4Nix-R36H-Resgate.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
ROOT="$TMP/Fire4Nix"
mkdir -p "$ROOT/bin" "$ROOT/runtime/lib" "$ROOT/runtime/libexec/wpe-webkit-2.0" "$ROOT/www" "$TMP/logs" "$TMP/run"
cat > "$ROOT/bin/fire4nix-wpe-platform" <<'MOCK'
#!/bin/sh
echo "MOCK_BROWSER_URL=$1"
echo "MOCK_LIBRARY_PATH=$LD_LIBRARY_PATH"
echo "MOCK_WPE_PROCESS_DIR=$WEBKIT_EXEC_PATH"
exit "${MOCK_EXIT:-0}"
MOCK
chmod +x "$ROOT/bin/fire4nix-wpe-platform"
: > "$ROOT/runtime/lib/libWPEWebKit-2.0.so.1"
: > "$ROOT/www/inicio.html"
for X in WPEWebProcess WPENetworkProcess WPEGPUProcess; do
  printf '#!/bin/sh\n' > "$ROOT/runtime/libexec/wpe-webkit-2.0/$X"
  chmod +x "$ROOT/runtime/libexec/wpe-webkit-2.0/$X"
done
python3 - "$TMP/run/wayland-1" <<'PY'
import socket,sys
s=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM)
s.bind(sys.argv[1])
s.close()
PY
XDG_RUNTIME_DIR="$TMP/run" FIRE4NIX_LOG_DIR="$TMP/logs" sh "$SCRIPT" --root "$ROOT" --check > "$TMP/check.txt"
grep -q 'CHECK COMPLETED' "$TMP/check.txt"
XDG_RUNTIME_DIR="$TMP/run" FIRE4NIX_LOG_DIR="$TMP/logs" sh "$SCRIPT" --root "$ROOT" --normal > "$TMP/normal.txt"
grep -q 'native_exit_code=0' "$TMP/normal.txt"
set +e
XDG_RUNTIME_DIR="$TMP/run" FIRE4NIX_LOG_DIR="$TMP/logs" MOCK_EXIT=139 sh "$SCRIPT" --root "$ROOT" --stable > "$TMP/crash.txt"
STATUS=$?
set -e
[ "$STATUS" -eq 139 ] || { echo "Expected 139, got $STATUS"; exit 1; }
grep -q 'native_exit_code=139' "$TMP/logs/ultimo-diagnostico.txt"
grep -q 'MOCK_LIBRARY_PATH=' "$TMP/logs/ultimo-diagnostico.txt"
grep -q 'MOCK_WPE_PROCESS_DIR=' "$TMP/logs/ultimo-diagnostico.txt"
echo 'PASS: preflight, environment, normal exit, preserved SIGSEGV status'
