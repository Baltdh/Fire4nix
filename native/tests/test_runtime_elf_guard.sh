#!/bin/sh
# Regression tests for runtime selection and ELF64 AArch64 preflight.
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
T=$(mktemp -d)
WAYLAND_PID=""
cleanup() {
  [ -n "$WAYLAND_PID" ] && kill "$WAYLAND_PID" 2>/dev/null || true
  [ -n "$WAYLAND_PID" ] && wait "$WAYLAND_PID" 2>/dev/null || true
  rm -rf "$T"
}
trap cleanup 0

make_arm64_elf() {
  python3 - "$1" <<'PY'
import struct
import sys
ident = b"\x7fELF\x02\x01\x01" + b"\x00" * 9
header = struct.pack("<HHIQQQIHHHHHH", 3, 183, 1, 0, 0, 0, 0, 64, 56, 0, 64, 0, 0)
with open(sys.argv[1], "wb") as stream:
    stream.write(ident + header)
PY
}

make_runtime() {
  root=$1
  mkdir -p "$root/lib" "$root/libexec/wpe-webkit-2.0"
  make_arm64_elf "$root/lib/libWPEWebKit-2.0.so.1"
  for process in WPEWebProcess WPENetworkProcess WPEGPUProcess; do
    make_arm64_elf "$root/libexec/wpe-webkit-2.0/$process"
  done
}

PKG="$T/package/Fire4Nix"
mkdir -p "$PKG/bin" "$PKG/config" "$T/logs"
cp "$REPO/installer/Fire4Nix-Iniciar.sh" "$PKG/Fire4Nix-Iniciar.sh"
cp "$REPO/installer/Diagnosticar-Fire4Nix.sh" "$T/package/Diagnosticar-Fire4Nix.sh"
make_runtime "$PKG/runtime"

cat > "$PKG/bin/fire4nix-native-aarch64" <<'NATIVE'
#!/bin/sh
{
  printf 'native_called=yes\n'
  printf 'native_args=%s\n' "$*"
  printf 'native_ld_library_path=%s\n' "${LD_LIBRARY_PATH:-}"
  printf 'native_webkit_exec_path=%s\n' "${WEBKIT_EXEC_PATH:-}"
} >> "${FIRE4NIX_TEST_TRACE:?}"
exit 0
NATIVE
chmod +x "$PKG/bin/fire4nix-native-aarch64"

# Default runtime is package-local; inherited Ports paths are discarded.
TRACE="$T/native-trace.txt"
FIRE4NIX_TEST_TRACE="$TRACE" \
FIRE4NIX_LOG_DIR="$T/logs" \
LD_LIBRARY_PATH=/storage/games-internal/roms/tools/Fire4Nix/runtime/lib \
  sh "$PKG/Fire4Nix-Iniciar.sh" --check-library > "$T/valid.log" 2>&1
grep -Fxq 'native_called=yes' "$TRACE"
grep -Fxq "native_ld_library_path=$PKG/runtime/lib" "$TRACE"
grep -Fxq "native_webkit_exec_path=$PKG/runtime/libexec/wpe-webkit-2.0" "$TRACE"
grep -Fq 'library_path_mode=isolated_discarded_inherited_paths' "$T/valid.log"
grep -Fq "runtime_root=$PKG/runtime" "$T/valid.log"

# An explicitly selected second-SD runtime is supported, but is validated
# before the native loader is entered.
make_runtime "$T/external-runtime"
: > "$TRACE"
FIRE4NIX_RUNTIME_ROOT="$T/external-runtime" \
FIRE4NIX_TEST_TRACE="$TRACE" \
FIRE4NIX_LOG_DIR="$T/logs" \
  sh "$PKG/Fire4Nix-Iniciar.sh" --check-library > "$T/external.log" 2>&1
grep -Fxq "native_ld_library_path=$T/external-runtime/lib" "$TRACE"
grep -Fq "runtime_root=$T/external-runtime" "$T/external.log"

# The first-test wrapper must also resolve an explicitly split runtime and
# pass it through to every launcher stage.
mkdir -p "$PKG/www" "$T/fakebin" "$T/first-report"
printf '<!doctype html><title>Fire4Nix offline fixture</title>\\n' > "$PKG/www/primeiro-teste.html"
cp "$REPO/installer/www/inicio.html" "$PKG/www/inicio.html"
cp "$REPO/installer/Fire4Nix-Primeiro-Teste-R36.sh" "$T/package/Fire4Nix-Primeiro-Teste-R36.sh"
cat > "$T/fakebin/uname" <<'UNAME'
#!/bin/sh
case "${1:-}" in
  -m) echo aarch64 ;;
  -r) echo 7.1.2 ;;
  *) /usr/bin/uname "$@" ;;
esac
UNAME
chmod +x "$T/fakebin/uname"
mkdir -p "$T/fake-wayland"
python3 - "$T/fake-wayland/wayland-1" <<'PY' &
import socket, sys, time
sock = socket.socket(socket.AF_UNIX)
sock.bind(sys.argv[1])
sock.listen(1)
while True:
    time.sleep(1)
PY
WAYLAND_PID=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -S "$T/fake-wayland/wayland-1" ] && break
  sleep 0.1
done
[ -S "$T/fake-wayland/wayland-1" ]
mv "$PKG/runtime" "$T/package-runtime-backup"
: > "$TRACE"
PATH="$T/fakebin:$PATH" \
XDG_RUNTIME_DIR="$T/fake-wayland" WAYLAND_DISPLAY=wayland-1 \
FIRE4NIX_RUNTIME_ROOT="$T/external-runtime" \
FIRE4NIX_TEST_TRACE="$TRACE" \
FIRE4NIX_GAMEPAD=0 \
FIRE4NIX_LOG_DIR="$T/logs" \
FIRE4NIX_TEST_REPORT_DIR="$T/first-report" \
  sh "$T/package/Fire4Nix-Primeiro-Teste-R36.sh" --preflight > "$T/first-test.log" 2>&1
grep -Fxq "runtime_root=$T/external-runtime" "$T/first-report/Primeiro-Teste-R36H-ULTIMO.txt"
grep -Fq 'offline_html_js_css_click=PASS' "$T/first-test.log"
grep -Fq 'home_ui_dom_keyboard_compact_form_shortcuts_focus=PASS' "$T/first-test.log"
grep -Fq 'native_args=--verify-home /' "$TRACE"
grep -Fq 'sandbox with space/Fire4Nix/www/inicio.html' "$TRACE"
grep -Fq 'native_called=yes' "$TRACE"
mv "$T/package-runtime-backup" "$PKG/runtime"

# A corrupt or foreign library must fail before dlopen/native execution.
printf 'not an ELF shared object' > "$PKG/runtime/lib/libWPEWebKit-2.0.so.1"
: > "$TRACE"
set +e
FIRE4NIX_TEST_TRACE="$TRACE" FIRE4NIX_LOG_DIR="$T/logs" \
  sh "$PKG/Fire4Nix-Iniciar.sh" --check-library > "$T/invalid.log" 2>&1
rc=$?
set -e
[ "$rc" -eq 79 ]
[ ! -s "$TRACE" ]
grep -Fq 'not a valid ELF64 AArch64 object' "$T/invalid.log"

# The diagnostic must not call a non-empty text file a working WPE library.
mkdir -p "$T/bad-runtime/lib" "$T/roms/tools/Fire4Nix/runtime/lib"
printf 'invalid header' > "$T/bad-runtime/lib/libWPEWebKit-2.0.so.1"
FIRE4NIX_DIAGNOSTIC_RUNTIME="$T/bad-runtime" \
FIRE4NIX_DIAGNOSTIC_OUT="$T/invalid-report.txt" \
  sh "$T/package/Diagnosticar-Fire4Nix.sh" > "$T/invalid-diagnostic.log" 2>&1
grep -Fxq 'WPE_library=invalid_elf' "$T/invalid-report.txt"
grep -Fxq "WPE_runtime_source=$T/bad-runtime" "$T/invalid-report.txt"
grep -Fxq 'WPE_runtime_error=not_elf64_little_endian_aarch64' "$T/invalid-report.txt"
grep -Fxq 'WPEPlatform_preflight=skipped_invalid_runtime_elf' "$T/invalid-report.txt"

# Without an explicit override, an invalid local runtime is skipped and a
# valid external tools runtime can be selected. A valid ELF header is required.
make_arm64_elf "$T/roms/tools/Fire4Nix/runtime/lib/libWPEWebKit-2.0.so.1"
FIRE4NIX_ROMS="$T/roms" \
FIRE4NIX_DIAGNOSTIC_OUT="$T/fallback-report.txt" \
  sh "$T/package/Diagnosticar-Fire4Nix.sh" --safe > "$T/fallback.log" 2>&1
grep -Fxq 'WPE_library=present' "$T/fallback-report.txt"
grep -Fxq "WPE_runtime_source=$T/roms/tools/Fire4Nix/runtime" "$T/fallback-report.txt"
grep -Fxq "invalid_wpe_runtime_candidate=$PKG/runtime" "$T/fallback-report.txt"

echo 'PASS: ELF64 AArch64 gate, split-SD runtime selection and stale LD_LIBRARY_PATH isolation.'
