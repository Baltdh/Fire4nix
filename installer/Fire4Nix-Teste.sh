#!/bin/sh
# Fire4Nix 1.01 R36H: offline, non-destructive test and report from ROCKNIX.
# No downloads, firmware/OS edits, personal file access or secret collection.
set -u
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 2
ROOT="$HERE/Fire4Nix"
[ -s "$ROOT/bin/fire4nix-native-aarch64" ] || ROOT="$HERE"
MODE=${1:---screen}
case "$MODE" in --safe|--screen|--check|--visual|--collect) ;; *) echo "Use: sh Fire4Nix-Teste.sh [--safe|--screen|--check|--visual|--collect]" >&2; exit 2 ;; esac
# Keep the report on /storage when possible; otherwise local or /tmp.
REPORT_DIR=${FIRE4NIX_TEST_REPORT_DIR:-}
if [ -z "$REPORT_DIR" ]; then
  if [ -d /storage ] && [ -w /storage ]; then
    REPORT_DIR=/storage/Fire4Nix-Teste
  elif [ -w "$HERE" ]; then
    REPORT_DIR="$HERE/Fire4Nix-Teste"
  else
    REPORT_DIR=${TMPDIR:-/tmp}/Fire4Nix-Teste
  fi
fi
if ! mkdir -p "$REPORT_DIR" 2>/dev/null; then
  echo "Fire4Nix: unable to create test report directory $REPORT_DIR" >&2
  exit 73
fi
REPORT=$(mktemp "$REPORT_DIR/Fire4Nix-Teste-101-XXXXXX.txt") || exit 73
DIAG="$REPORT_DIR/Fire4Nix-Diagnostico-101.txt"
LATEST="$REPORT_DIR/Fire4Nix-Ultimo-Teste.txt"
STATUS_FILE="$REPORT_DIR/Fire4Nix-Resumo-101.txt"
BIN="$ROOT/bin/fire4nix-native-aarch64"
DIAG_SCRIPT="$HERE/Diagnosticar-Fire4Nix.sh"
[ -f "$DIAG_SCRIPT" ] || DIAG_SCRIPT="$ROOT/Diagnosticar-Fire4Nix.sh"

installed_root=""
for dir in "$ROOT" \
  "${FIRE4NIX_ROMS:-/no-roms}/ports/fire4nix-completo" \
  /storage/games-internal/roms/ports/fire4nix-completo \
  /storage/games-external/roms/ports/fire4nix-completo \
  /storage/roms/ports/fire4nix-completo; do
  if [ -s "$dir/runtime/lib/libWPEWebKit-2.0.so.1" ] &&
     [ -f "$dir/Fire4Nix-Iniciar.sh" ]; then installed_root="$dir"; break; fi
done

exit_visual=NA
exit_selftest=NA
exit_diagnostic=NA
{
  echo 'FIRE4NIX 1.01 / ROCKNIX R36H TEST REPORT'
  date '+test_date=%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || true
  echo "mode=$MODE"
  echo "package_root=$ROOT"
  echo "installed_runtime_root=${installed_root:-not_found}"
  echo "architecture=$(uname -m 2>/dev/null)"
  echo "kernel=$(uname -r 2>/dev/null)"
  if [ -s "$BIN" ]; then
    echo 'native_binary=present'
    if [ -x "$BIN" ]; then
      "$BIN" --selftest 2>&1
      exit_selftest=$?
    else
      sh -c 'exit 126'
      exit_selftest=$?
    fi
  else
    echo 'native_binary=missing'
    exit_selftest=127
  fi
  echo "selftest_exit=$exit_selftest"
  if [ -f "$DIAG_SCRIPT" ]; then
    if [ "$MODE" = --safe ]; then
      FIRE4NIX_DIAGNOSTIC_OUT="$DIAG" sh "$DIAG_SCRIPT" --safe >/dev/null 2>&1
    else
      FIRE4NIX_DIAGNOSTIC_OUT="$DIAG" sh "$DIAG_SCRIPT" >/dev/null 2>&1
    fi
    exit_diagnostic=$?
    echo "diagnostic_exit=$exit_diagnostic"
    if [ -f "$DIAG" ]; then
      grep -E '^(arch=|WPE_library=|WPE_runtime_source=|WPE_version=|WPEWebProcess=|WPENetworkProcess=|WPEGPUProcess=|gpu_runtime_profile=|gpu_process_required=|WPEPlatform_fault_stage=|WPEPlatform_preflight=|WPEPlatform_preflight_exit=|WPEPlatform_preflight_note=|wayland_socket=|alternate_wayland_socket=|drm_render_node=|gptokeyb=|uinput=|GRAPHICS_STATUS=)' "$DIAG" || true
    fi
  else
    echo 'diagnostic_exit=127'
    echo 'diagnostic_reason=missing_script'
  fi
  if [ "$MODE" = --visual ]; then
    if [ -z "$installed_root" ]; then
      echo 'visual_test=SKIPPED_NO_INSTALLED_RUNTIME'
      exit_visual=127
    else
      echo "visual_test=STARTED_OFFLINE_HTML"
      # This uses WebKit's existing built-in smoke timeout. It is not a
      # simulated display; actual ROCKNIX must render successfully.
      if command -v timeout >/dev/null 2>&1; then
        timeout 25 sh "$installed_root/Fire4Nix-Iniciar.sh" --smoke \
          "file://$installed_root/www/inicio.html" 2>&1
        exit_visual=$?
      else
        sh "$installed_root/Fire4Nix-Iniciar.sh" --smoke \
          "file://$installed_root/www/inicio.html" 2>&1
        exit_visual=$?
      fi
      echo "visual_smoke_exit=$exit_visual"
      if [ "$exit_visual" -eq 0 ]; then
        echo 'visual_test_result=PAGE_LOAD_SIGNAL_ONLY_NOT_PROOF_OF_VISIBLE_WINDOW'
      else
        echo 'visual_test_result=FAILED_OR_TIMED_OUT'
      fi
    fi
  else
    echo 'visual_test=NOT_RUN_MANUALLY_USE_--visual'
  fi
  if [ -r /storage/Fire4Nix-ultimo-resultado.txt ]; then
    echo 'previous_browser_exit:'
    grep -E '^(version=|mode=|fire4nix_exit_code=|error=|gamepad=|platform=)' \
      /storage/Fire4Nix-ultimo-resultado.txt | tail -n 12 || true
  fi
  echo 'Privacy: no network calls, passwords, complete terminal logs or input events.'
  echo 'GRAPHICAL_HARDWARE_STATUS=UNVERIFIED_UNTIL_PHYSICAL_TEST'
  echo 'END'
} > "$REPORT" 2>&1
cp "$REPORT" "$LATEST" 2>/dev/null || true
{
  echo 'FIRE4NIX 1.01 / RESUMO PARA FOTO'
  grep -E '^(native_binary=|selftest_exit=|WPE_library=|WPE_version=|WPEPlatform_fault_stage=|WPEPlatform_preflight=|WPEPlatform_preflight_exit=|wayland_socket=|visual_smoke_exit=|visual_test=|visual_test_result=|GRAPHICAL_HARDWARE_STATUS=)' "$REPORT" | cut -c 1-101 || true
  echo 'FIM DO RESUMO'
} > "$STATUS_FILE"
if [ "$MODE" = --safe ] || [ "$MODE" = --screen ] ||
   [ "$MODE" = --visual ] || [ "$MODE" = --check ]; then
  cat "$STATUS_FILE"
  printf 'Relatorio completo: %s\n' "$LATEST"
  printf 'Diagnostico WPE: %s\n' "$DIAG"
else
  printf 'Resultado arquivado: %s\n' "$LATEST"
fi
# Diagnostic failures are findings rather than a script execution failure;
# --visual returns the meaningful WebKit error for callers/CI.
if [ "$MODE" = --visual ]; then
  [ "$exit_visual" = NA ] && exit 127
  exit "$exit_visual"
fi
exit 0
