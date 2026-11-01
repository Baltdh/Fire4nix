#!/bin/sh
# Fire4Nix 1.01 R36H: offline, non-destructive test and report from ROCKNIX.
# No downloads, firmware/OS edits, personal file access or secret collection.
set -u
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 2
ROOT="$HERE/Fire4Nix"
[ -s "$ROOT/bin/fire4nix-native-aarch64" ] || ROOT="$HERE"
MODE=${1:---screen}
case "$MODE" in --safe|--screen|--check|--visual|--visual-live|--collect) ;; *) echo "Use: sh Fire4Nix-Teste.sh [--safe|--screen|--check|--visual|--visual-live|--collect]" >&2; exit 2 ;; esac
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
REPORT=$(mktemp "$REPORT_DIR/Fire4Nix-Teste-101-txt-XXXXXX") || exit 73
DIAG="$REPORT_DIR/Fire4Nix-Diagnostico-101.txt"
LATEST="$REPORT_DIR/Fire4Nix-Ultimo-Teste.txt"
STATUS_FILE="$REPORT_DIR/Fire4Nix-Resumo-101.txt"
BIN="$ROOT/bin/fire4nix-native-aarch64"
DIAG_SCRIPT="$HERE/Diagnosticar-Fire4Nix.sh"
[ -f "$DIAG_SCRIPT" ] || DIAG_SCRIPT="$ROOT/Diagnosticar-Fire4Nix.sh"

installed_root=""
for dir in "$HERE/../Fire4Nix" \
  "${FIRE4NIX_ROMS:-/no-roms}/ports/Fire4Nix" \
  "${FIRE4NIX_ROMS:-/no-roms}/ports/fire4nix-completo" \
  "$ROOT" \
  /storage/games-internal/roms/ports/Fire4Nix \
  /storage/games-external/roms/ports/Fire4Nix \
  /storage/roms/ports/Fire4Nix \
  /storage/games-internal/roms/ports/fire4nix-completo \
  /storage/games-external/roms/ports/fire4nix-completo \
  /storage/roms/ports/fire4nix-completo; do
  if [ -s "$dir/bin/fire4nix-native-aarch64" ] &&
     [ -f "$dir/Fire4Nix-Iniciar.sh" ]; then
    installed_root=$(CDPATH= cd -- "$dir" && pwd -P) || exit 127
    break
  fi
done

is_elf64_aarch64() {
  file_path=$1
  [ -f "$file_path" ] && [ -r "$file_path" ] && [ ! -L "$file_path" ] || return 1
  command -v od >/dev/null 2>&1 || return 1
  elf_bytes=$(od -An -v -t x1 -N20 "$file_path" 2>/dev/null | tr '\n' ' ') || return 1
  set -- $elf_bytes
  [ "$#" -ge 20 ] || return 1
  [ "$1" = 7f ] && [ "$2" = 45 ] && [ "$3" = 4c ] && [ "$4" = 46 ] &&
  [ "$5" = 02 ] && [ "$6" = 01 ] && [ "${19}" = b7 ] && [ "${20}" = 00 ]
}

installed_runtime_root=""
invalid_runtime_candidate=""
if [ -n "${FIRE4NIX_RUNTIME_ROOT:-}" ]; then
  candidate=$FIRE4NIX_RUNTIME_ROOT
  case "$candidate" in /*) ;; *) candidate="${installed_root:-$ROOT}/$candidate" ;; esac
  if is_elf64_aarch64 "$candidate/lib/libWPEWebKit-2.0.so.1"; then
    installed_runtime_root=$(CDPATH= cd -- "$candidate" && pwd -P) || exit 127
  else
    invalid_runtime_candidate=$candidate
  fi
else
  for candidate in "${installed_root:-$ROOT}/runtime" "$ROOT/runtime" \
    /storage/games-internal/roms/tools/Fire4Nix/runtime \
    /storage/games-external/roms/tools/Fire4Nix/runtime \
    /storage/roms/tools/Fire4Nix/runtime \
    /storage/games-internal/roms/ports/fire4nix-completo/runtime \
    /storage/games-external/roms/ports/fire4nix-completo/runtime \
    /storage/roms/ports/fire4nix-completo/runtime; do
    if is_elf64_aarch64 "$candidate/lib/libWPEWebKit-2.0.so.1"; then
      installed_runtime_root=$(CDPATH= cd -- "$candidate" && pwd -P) || exit 127
      break
    elif [ -s "$candidate/lib/libWPEWebKit-2.0.so.1" ] && [ -z "$invalid_runtime_candidate" ]; then
      invalid_runtime_candidate=$candidate
    fi
  done
fi

if [ -n "$installed_runtime_root" ]; then
  export FIRE4NIX_RUNTIME_ROOT="$installed_runtime_root"
  if [ -z "${FIRE4NIX_DIAGNOSTIC_RUNTIME:-}" ]; then
    FIRE4NIX_DIAGNOSTIC_RUNTIME=$installed_runtime_root
    export FIRE4NIX_DIAGNOSTIC_RUNTIME
  fi
elif [ -n "$invalid_runtime_candidate" ] && [ -z "${FIRE4NIX_DIAGNOSTIC_RUNTIME:-}" ]; then
  FIRE4NIX_DIAGNOSTIC_RUNTIME=$invalid_runtime_candidate
  export FIRE4NIX_DIAGNOSTIC_RUNTIME
fi

exit_visual=NA
exit_selftest=NA
exit_diagnostic=NA
{
  echo 'FIRE4NIX 1.01 / ROCKNIX R36H TEST REPORT'
  date '+test_date=%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || true
  echo "mode=$MODE"
  echo "package_root=$ROOT"
  echo "installed_runtime_root=${installed_runtime_root:-not_found}"
  [ -n "$invalid_runtime_candidate" ] && echo "invalid_runtime_candidate=$invalid_runtime_candidate"
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
    # A failed WPE preflight is diagnostic data, not a reason to skip
    # the separate visual smoke probe or its meaningful launcher exit code.
    set +e
    if [ "$MODE" = --safe ]; then
      FIRE4NIX_DIAGNOSTIC_OUT="$DIAG" sh "$DIAG_SCRIPT" --safe >/dev/null 2>&1
    else
      FIRE4NIX_DIAGNOSTIC_OUT="$DIAG" sh "$DIAG_SCRIPT" >/dev/null 2>&1
    fi
    exit_diagnostic=$?
    set -e
    echo "diagnostic_exit=$exit_diagnostic"
    if [ -f "$DIAG" ]; then
      grep -E '^(arch=|WPE_library=|WPE_runtime_source=|WPE_version=|WPEWebProcess=|WPENetworkProcess=|WPEGPUProcess=|gpu_runtime_profile=|gpu_process_required=|WPEPlatform_fault_stage=|WPEPlatform_preflight=|WPEPlatform_preflight_exit=|WPEPlatform_preflight_note=|wayland_socket=|alternate_wayland_socket=|drm_render_node=|gptokeyb=|uinput=|GRAPHICS_STATUS=)' "$DIAG" || true
    fi
  else
    echo 'diagnostic_exit=127'
    echo 'diagnostic_reason=missing_script'
  fi
  if [ "$MODE" = --visual ] || [ "$MODE" = --visual-live ]; then
    if [ -z "$installed_root" ] || [ -z "$installed_runtime_root" ]; then
      echo 'visual_test=SKIPPED_NO_VALID_WPE_RUNTIME'
      exit_visual=127
    else
      echo 'visual_test_page=primeiro-teste.html'
      echo 'visual_test_manual_checks=HTML_CSS_THREE_COLORS_AND_JS_OK'
      echo 'visual_test_network_required=no'
      if [ ! -s "$installed_root/www/primeiro-teste.html" ]; then
        echo 'visual_test=BLOCKED_MISSING_OFFLINE_TEST_PAGE'
        exit_visual=127
      else
      if [ "$MODE" = --visual-live ]; then
        echo 'visual_test=STARTED_INTERACTIVE_OFFLINE_HTML'
        echo 'visual_live_manual_action=CONFIRM_THREE_COLORS_JS_OK_AND_BUTTON_THEN_EXIT'
        # Unlike --smoke, keep the page open for the user. The launcher
        # manages gamepad mapping while the browser is running.
        # Do not impose a 25-second timeout on the physical display test.
        FIRE4NIX_RUNTIME_ROOT="$installed_runtime_root" sh "$installed_root/Fire4Nix-Iniciar.sh" --open \
          "$installed_root/www/primeiro-teste.html" 2>&1
        exit_visual=$?
      else
        echo "visual_test=STARTED_OFFLINE_HTML"
        # Bounded page-load signal for automated diagnostics, never proof
        # of rendered pixels on the physical 640x480 LCD.
        if command -v timeout >/dev/null 2>&1; then
          timeout 25 env FIRE4NIX_RUNTIME_ROOT="$installed_runtime_root" sh "$installed_root/Fire4Nix-Iniciar.sh" --smoke \
            "$installed_root/www/primeiro-teste.html" 2>&1
          exit_visual=$?
        else
          env FIRE4NIX_RUNTIME_ROOT="$installed_runtime_root" sh "$installed_root/Fire4Nix-Iniciar.sh" --smoke \
            "$installed_root/www/primeiro-teste.html" 2>&1
          exit_visual=$?
        fi
      fi
      fi
      if [ "$MODE" = --visual-live ]; then
        echo "visual_live_exit=$exit_visual"
        if [ "$exit_visual" -eq 0 ]; then
          echo 'visual_test_result=INTERACTIVE_SESSION_ENDED_MANUAL_FRAME_CONFIRMATION_REQUIRED'
        else
          echo 'visual_test_result=INTERACTIVE_SESSION_FAILED_OR_EXITED'
        fi
      else
        echo "visual_smoke_exit=$exit_visual"
        if [ "$exit_visual" -eq 0 ]; then
          echo 'visual_test_result=PAGE_LOAD_SIGNAL_ONLY_MANUALLY_CONFIRM_CSS_AND_JS'
        else
          echo 'visual_test_result=FAILED_OR_TIMED_OUT'
        fi
      fi
    fi
  else
    echo 'visual_test=NOT_RUN_MANUALLY_USE_--visual_OR_--visual-live'
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
  grep -E '^(native_binary=|selftest_exit=|WPE_library=|WPE_runtime_source=|WPE_runtime_error=|invalid_wpe_runtime_candidate=|WPE_version=|WPEPlatform_fault_stage=|WPEPlatform_preflight=|WPEPlatform_preflight_exit=|wayland_socket=|visual_test_page=|visual_test_manual_checks=|visual_smoke_exit=|visual_live_exit=|visual_test=|visual_test_result=|GRAPHICAL_HARDWARE_STATUS=)' "$REPORT" | cut -c 1-101 || true
  echo 'FIM DO RESUMO'
} > "$STATUS_FILE"
if [ "$MODE" = --safe ] || [ "$MODE" = --screen ] ||
   [ "$MODE" = --visual ] || [ "$MODE" = --visual-live ] || [ "$MODE" = --check ]; then
  cat "$STATUS_FILE"
  printf 'Relatorio completo: %s\n' "$LATEST"
  printf 'Diagnostico WPE: %s\n' "$DIAG"
else
  printf 'Resultado arquivado: %s\n' "$LATEST"
fi
# Diagnostic failures are findings rather than a script execution failure;
# --visual returns the meaningful WebKit error for callers/CI.
if [ "$MODE" = --visual ] || [ "$MODE" = --visual-live ]; then
  [ "$exit_visual" = NA ] && exit 127
  exit "$exit_visual"
fi
exit 0
