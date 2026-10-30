#!/bin/sh
# Fire4Nix R36H first physical test: preflight + real offline WebKit check.
# This script never installs system libraries, changes firmware or downloads data.
set -u
umask 077

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 2
ROOT="$HERE/Fire4Nix"
[ -s "$ROOT/bin/fire4nix-native-aarch64" ] || ROOT="$HERE"
BIN="$ROOT/bin/fire4nix-native-aarch64"
LAUNCHER="$ROOT/Fire4Nix-Iniciar.sh"
PAGE="$ROOT/www/primeiro-teste.html"
MODE=${1:---preflight}

case "$MODE" in
  --preflight|--open|--graphics-probe) ;;
  *) echo "Uso: sh Fire4Nix-Primeiro-Teste-R36.sh [--graphics-probe|--preflight|--open]" >&2; exit 2 ;;
esac

REPORT_DIR=${FIRE4NIX_TEST_REPORT_DIR:-}
if [ -z "$REPORT_DIR" ]; then
  if [ -d /storage ] && [ -w /storage ]; then
    REPORT_DIR=/storage/Fire4Nix-Primeiro-Teste
  elif [ -w "$HERE" ]; then
    REPORT_DIR="$HERE/Fire4Nix-Primeiro-Teste"
  else
    REPORT_DIR=${TMPDIR:-/tmp}/Fire4Nix-Primeiro-Teste
  fi
fi
mkdir -p "$REPORT_DIR" 2>/dev/null || {
  echo "ERRO: nao foi possivel criar $REPORT_DIR" >&2
  exit 73
}
REPORT=$(mktemp "$REPORT_DIR/Primeiro-Teste-R36H-XXXXXX.txt") || exit 73
SUMMARY="$REPORT_DIR/Primeiro-Teste-R36H-RESUMO.txt"
: > "$REPORT" || exit 73

log() { printf '%s\n' "$*" | tee -a "$REPORT"; }
finish() {
  code=$?
  printf 'first_test_exit=%s\n' "$code" >> "$REPORT"
  cp "$REPORT" "$REPORT_DIR/Primeiro-Teste-R36H-ULTIMO.txt" 2>/dev/null || true
  {
    echo 'FIRE4NIX R36H - RESUMO DO PRIMEIRO TESTE'
    grep -E '^(device_arch=|native_selftest=|wpe_library=|wpeplatform_symbols=|offline_html_js_css_click=|visual_session=|graphics_probe_exit=|EGL_PROBE=|egl_initialize=|egl_get_display=|gles_renderer=|wayland_socket=|first_test_exit=|GRAPHICAL_FRAME_VERIFIED=)' "$REPORT" || true
    echo "full_report=$REPORT_DIR/Primeiro-Teste-R36H-ULTIMO.txt"
  } > "$SUMMARY"
  cat "$SUMMARY"
  exit "$code"
}
trap finish 0

fail() {
  code=$1
  shift
  log "FALHA: $*"
  exit "$code"
}

run_stage() {
  label=$1
  mode=$2
  url=${3:-}
  stage_log="$REPORT_DIR/$label.log"
  log "TEST_BEGIN=$label"
  if [ -n "$url" ]; then
    if command -v timeout >/dev/null 2>&1; then
      timeout --signal=TERM --kill-after=5s 75s sh "$LAUNCHER" "$mode" "$url" > "$stage_log" 2>&1
      rc=$?
    else
      sh "$LAUNCHER" "$mode" "$url" > "$stage_log" 2>&1
      rc=$?
    fi
  else
    if command -v timeout >/dev/null 2>&1; then
      timeout --signal=TERM --kill-after=5s 45s sh "$LAUNCHER" "$mode" > "$stage_log" 2>&1
      rc=$?
    else
      sh "$LAUNCHER" "$mode" > "$stage_log" 2>&1
      rc=$?
    fi
  fi
  printf 'TEST_%s_EXIT=%s\n' "$label" "$rc" | tee -a "$REPORT"
  tail -n 32 "$stage_log" 2>/dev/null | tee -a "$REPORT"
  [ "$rc" -eq 0 ] || return "$rc"
  return 0
}

log 'FIRE4NIX_R36H_FIRST_TEST=1'
log "test_mode=$MODE"
log "package_root=$ROOT"
log "device_arch=$(uname -m 2>/dev/null || echo unknown)"
log "device_kernel=$(uname -r 2>/dev/null || echo unknown)"
log "device_glibc=$(getconf GNU_LIBC_VERSION 2>/dev/null || echo unavailable)"
log 'FIRMWARE_MODIFIED=no'
log 'SYSTEM_LIBRARIES_INSTALLED=no'
log 'NETWORK_REQUIRED=no'
log 'WPE_RUNTIME_REPLACED=no'

# The EGL probe is independent from WebKit. It diagnoses the device's system
# EGL/GLES stack before the browser is loaded and never modifies global state.
if [ "$MODE" = --graphics-probe ]; then
  [ "$(uname -m 2>/dev/null)" = aarch64 ] || fail 126 "Este teste requer ROCKNIX ARM64 (aarch64)."
  EGL_PROBE="$HERE/Fire4Nix-EGL-R36H.py"
  [ -s "$EGL_PROBE" ] || fail 127 "Diagnostico EGL ausente: $EGL_PROBE"
  command -v python3 >/dev/null 2>&1 || fail 127 "Python 3 nao encontrado no ROCKNIX."
  command -v timeout >/dev/null 2>&1 || fail 127 "O comando timeout e necessario para limitar o teste EGL a 15 segundos."
  log 'graphics_probe_scope=system_EGL_GLES2_offscreen_pbuffer_1x1'
  log 'graphics_probe_timeout=15s'
  log 'GRAPHICAL_FRAME_VERIFIED=no'
  if MALI_DEFAULT_DISPLAY="${MALI_DEFAULT_DISPLAY:-wayland}" timeout 15s python3 "$EGL_PROBE" >> "$REPORT" 2>&1; then
    log 'graphics_probe_exit=0'
    log 'EGL_PROBE=PASS_OFFSCREEN_CONTEXT_ONLY'
    exit 0
  else
    probe_rc=$?
    log "graphics_probe_exit=$probe_rc"
    case "$probe_rc" in
      124|137) log 'EGL_PROBE=TIMEOUT_OR_KILLED' ;;
      2) log 'EGL_PROBE=SYSTEM_EGL_LIBRARY_UNAVAILABLE' ;;
      3|4) log 'EGL_PROBE=DISPLAY_OR_EGL_INITIALIZATION_FAILED' ;;
      5|6|7|8|9|10) log 'EGL_PROBE=GLES2_CONTEXT_SETUP_FAILED' ;;
      *) log 'EGL_PROBE=FAILED_CHECK_PROBE_LOG' ;;
    esac
    exit "$probe_rc"
  fi
fi

[ "$(uname -m 2>/dev/null)" = aarch64 ] || fail 126 "Este pacote requer ROCKNIX ARM64 (aarch64)."
[ -s "$BIN" ] || fail 127 "Executavel Fire4Nix ausente: $BIN"
[ -f "$LAUNCHER" ] || fail 127 "Launcher principal ausente: $LAUNCHER"
[ -s "$ROOT/runtime/lib/libWPEWebKit-2.0.so.1" ] || fail 127 "Runtime WPE local ausente."
[ -s "$ROOT/runtime/libexec/wpe-webkit-2.0/WPEWebProcess" ] || fail 127 "WPEWebProcess ausente."
[ -s "$ROOT/runtime/libexec/wpe-webkit-2.0/WPENetworkProcess" ] || fail 127 "WPENetworkProcess ausente."
[ -s "$PAGE" ] || fail 127 "Pagina offline de teste ausente."

if ! "$BIN" --selftest > "$REPORT_DIR/selftest.log" 2>&1; then
  cat "$REPORT_DIR/selftest.log" | tee -a "$REPORT"
  fail 126 "Selftest ELF AArch64 falhou."
fi
cat "$REPORT_DIR/selftest.log" | tee -a "$REPORT"
log 'native_selftest=PASS'

run_stage WPE-LIBRARY --check-library || fail 127 "O carregador nao conseguiu abrir o WPE privado."
log 'wpe_library=PASS'

run_stage WPEPLATFORM-ABI --check-platform || fail 78 "A biblioteca nao expoe toda a API WPEPlatform necessaria."
log 'wpeplatform_symbols=PASS'

run_stage OFFLINE-ENGINE --verify-offline "file://$PAGE" || fail 4 "O WebKit nao passou no teste DOM/JavaScript/CSS/clique."
log 'offline_html_js_css_click=PASS'
log 'ENGINE_FUNCTIONAL_TEST=PASS'
log 'GRAPHICAL_FRAME_VERIFIED=no'
log 'GRAPHICAL_FRAME_INSTRUCTIONS=Use --open to keep the 640x480 page visible and confirm the three color blocks and JS OK.'

if [ "$MODE" = --open ]; then
  log 'visual_session=STARTED'
  log 'visual_manual_checks=THREE_COLOR_BLOCKS,JS_OK,TEST_BUTTON_CLICK'
  sh "$LAUNCHER" --open "file://$PAGE" >> "$REPORT" 2>&1
  visual_rc=$?
  log "visual_session_exit=$visual_rc"
  if [ "$visual_rc" -eq 0 ]; then
    log 'visual_session=EXITED_NORMALLY_MANUAL_PIXEL_CONFIRMATION_REQUIRED'
  else
    log 'visual_session=FAILED_OR_CRASHED'
    exit "$visual_rc"
  fi
else
  log 'visual_session=NOT_STARTED_USE_--open_AFTER_PREFLIGHT'
fi
exit 0
