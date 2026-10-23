#!/bin/sh
# Exercise the packaged on-device test kit on the ARM64 GitHub runner.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
T=$(mktemp -d)
trap 'rm -rf "$T"' 0
: "${FIRE4NIX_TEST_PKG:?set FIRE4NIX_TEST_PKG to built distribution directory}"
mkdir -p "$T/roms/ports" "$T/reports" "$T/pkg"
cp -a "${FIRE4NIX_TEST_PKG}/." "$T/pkg/"
echo 'preserve-browser' > "$T/roms/ports/Fire4Nix.sh"
FIRE4NIX_ROMS="$T/roms" sh "$T/pkg/Habilitar-Teste-Ports.sh" > "$T/enable.log"
grep -q 'NO_WEBKIT_COPIED=1' "$T/enable.log"
grep -q 'preserve-browser' "$T/roms/ports/Fire4Nix.sh"
test -f "$T/roms/ports/Fire4Nix-Teste-101.sh"
test -f "$T/roms/ports/Fire4Nix-Grafico-101.sh"
test -f "$T/roms/ports/Fire4Nix-Tela-101.sh"
test -s "$T/roms/ports/.Fire4Nix-Teste-101/Fire4Nix/www/primeiro-teste.html"
test ! -d "$T/roms/ports/.Fire4Nix-Teste-101/Fire4Nix/runtime"
# Running via the actual Ports wrapper does not require a WebKit installation.
FIRE4NIX_ROMS="$T/roms" FIRE4NIX_TEST_REPORT_DIR="$T/reports" \
  sh "$T/roms/ports/Fire4Nix-Teste-101.sh" > "$T/screen.log"
grep -q 'RESUMO PARA FOTO' "$T/screen.log"
grep -q 'selftest_exit=0' "$T/screen.log"
grep -q 'WPE_library=missing' "$T/screen.log"
grep -q 'GRAPHICAL_HARDWARE_STATUS=UNVERIFIED' "$T/screen.log"
test -s "$T/reports/Fire4Nix-Ultimo-Teste.txt"
test -s "$T/reports/Fire4Nix-Diagnostico-101.txt"
test -s "$T/reports/Fire4Nix-Resumo-101.txt"
# A graphics test must refuse to claim success without installed WebKit.
set +e
FIRE4NIX_ROMS="$T/roms" FIRE4NIX_TEST_REPORT_DIR="$T/reports" \
  sh "$T/roms/ports/Fire4Nix-Grafico-101.sh" > "$T/visual-missing.log"
visual_missing=$?
set -e
test "$visual_missing" -eq 127
grep -q 'visual_test=SKIPPED_NO_INSTALLED_RUNTIME' "$T/reports/Fire4Nix-Ultimo-Teste.txt"
set +e
FIRE4NIX_ROMS="$T/roms" FIRE4NIX_TEST_REPORT_DIR="$T/reports" \
  sh "$T/roms/ports/Fire4Nix-Tela-101.sh" > "$T/live-missing.log"
live_missing=$?
set -e
test "$live_missing" -eq 127
grep -q 'visual_test=SKIPPED_NO_INSTALLED_RUNTIME' "$T/reports/Fire4Nix-Ultimo-Teste.txt"

# Simulated *installed* launcher: the test suite must record its actual exit.
mkdir -p "$T/roms/ports/fire4nix-completo/runtime/lib" \
 "$T/roms/ports/fire4nix-completo/www"
printf dummy > "$T/roms/ports/fire4nix-completo/runtime/lib/libWPEWebKit-2.0.so.1"
printf html > "$T/roms/ports/fire4nix-completo/www/inicio.html"
cat > "$T/roms/ports/fire4nix-completo/Fire4Nix-Iniciar.sh" <<'BROWSER'
#!/bin/sh
printf 'TEST_MODE=%s\nTEST_OFFLINE_PAGE=%s\n' "$1" "$2"
exit 70
BROWSER
# Regression: an installed runtime without the new dedicated offline
# first-frame page must explicitly refuse the graphics smoke (exit 127)
# rather than silently falling back to an unrelated home page.
set +e
FIRE4NIX_ROMS="$T/roms" FIRE4NIX_TEST_REPORT_DIR="$T/reports" \
  sh "$T/roms/ports/Fire4Nix-Grafico-101.sh" > "$T/visual-no-page.log"
visual_no_page=$?
set -e
test "$visual_no_page" -eq 127
grep -q 'visual_test=BLOCKED_MISSING_OFFLINE_TEST_PAGE' "$T/reports/Fire4Nix-Ultimo-Teste.txt"
grep -q 'visual_smoke_exit=127' "$T/reports/Fire4Nix-Ultimo-Teste.txt"
# Positive fixture must contain the real offline page. This preserves the
# preexisting assertion that the browser exit (70) is propagated exactly.
cp "$ROOT/installer/www/primeiro-teste.html" \
  "$T/roms/ports/fire4nix-completo/www/primeiro-teste.html"
set +e
FIRE4NIX_ROMS="$T/roms" FIRE4NIX_TEST_REPORT_DIR="$T/reports" \
  sh "$T/roms/ports/Fire4Nix-Grafico-101.sh" > "$T/visual-failed.log"
visual_failed=$?
set -e
test "$visual_failed" -eq 70
grep -q 'visual_smoke_exit=70' "$T/reports/Fire4Nix-Ultimo-Teste.txt"
grep -q 'visual_test_page=primeiro-teste.html' "$T/reports/Fire4Nix-Ultimo-Teste.txt"
grep -q 'visual_test_manual_checks=HTML_CSS_THREE_COLORS_AND_JS_OK' "$T/reports/Fire4Nix-Ultimo-Teste.txt"
grep -q 'visual_test_result=FAILED_OR_TIMED_OUT' "$T/reports/Fire4Nix-Ultimo-Teste.txt"
grep -Fq 'TEST_MODE=--smoke' "$T/visual-failed.log"
# The new dedicated Ports entry MUST start a persistent interactive browser.
# The fake launcher exits immediately with code 70; no pixels are asserted.
set +e
FIRE4NIX_ROMS="$T/roms" FIRE4NIX_TEST_REPORT_DIR="$T/reports" \
  sh "$T/roms/ports/Fire4Nix-Tela-101.sh" > "$T/live-failed.log"
live_failed=$?
set -e
test "$live_failed" -eq 70
grep -Fq 'TEST_MODE=--open' "$T/live-failed.log"
grep -Fq 'primeiro-teste.html' "$T/live-failed.log"
grep -Fq 'visual_test=STARTED_INTERACTIVE_OFFLINE_HTML' "$T/reports/Fire4Nix-Ultimo-Teste.txt"
grep -Fq 'visual_live_exit=70' "$T/reports/Fire4Nix-Ultimo-Teste.txt"
grep -Fq 'visual_test_result=INTERACTIVE_SESSION_FAILED_OR_EXITED' "$T/reports/Fire4Nix-Ultimo-Teste.txt"
if grep -Fq 'visual_smoke_exit=' "$T/reports/Fire4Nix-Ultimo-Teste.txt"; then
  echo 'ERROR: live mode reported smoke success' >&2
  exit 1
fi

grep -q 'primeiro-teste.html' "$T/visual-failed.log"
# Running the setup a second time must not overwrite existing browser/test kit.
FIRE4NIX_ROMS="$T/roms" sh "$T/pkg/Habilitar-Teste-Ports.sh" | grep -q 'already present'
grep -q 'preserve-browser' "$T/roms/ports/Fire4Nix.sh"
echo 'PASS: offline photo reports, live first frame mode, independent Ports entries, no runtime copied, missing WPE classification and visual exit propagation'
