#!/bin/sh
# Fire4Nix 1.07: investigate WebKit exit 139 without changing ROCKNIX.
# --safe never loads WPE. --trace runs only a native ABI preflight, no websites.
set -u
umask 077
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 2
MODE=${1:---safe}
case "$MODE" in --safe|--trace) ;; *) echo "Usage: sh Fire4Nix-Investigar-139.sh [--safe|--trace]" >&2; exit 2 ;; esac

REPORT_DIR=${FIRE4NIX_INVEST_REPORT_DIR:-}
if [ -z "$REPORT_DIR" ]; then
  if [ -d /storage ] && [ -w /storage ]; then
    REPORT_DIR=/storage/Fire4Nix-Investigacao-139
  elif [ -w "$HERE" ]; then
    REPORT_DIR="$HERE/Fire4Nix-Investigacao-139"
  else
    REPORT_DIR=${TMPDIR:-/tmp}/Fire4Nix-Investigacao-139
  fi
fi
mkdir -p "$REPORT_DIR" || exit 73
REPORT="$REPORT_DIR/Fire4Nix-139-ultimo.txt"
RUN_DIR=$(mktemp -d "$REPORT_DIR/exec-XXXXXX") || exit 73

bin_root=""
for root in "${FIRE4NIX_BINARY_ROOT:-}" "${FIRE4NIX_ROOT:-}" "$HERE/Fire4Nix" "$HERE" \
  "$HERE/fire4nix-completo" \
  /storage/games-internal/roms/ports/fire4nix-completo \
  /storage/games-external/roms/ports/fire4nix-completo \
  /storage/roms/ports/fire4nix-completo \
  /storage/games-internal/roms/tools/Fire4Nix \
  /storage/games-external/roms/tools/Fire4Nix \
  /storage/roms/tools/Fire4Nix; do
  [ -n "$root" ] && [ -d "$root" ] || continue
  if [ -s "$root/bin/fire4nix-native-aarch64" ]; then
    bin_root=$root
    break
  fi
done

# ROCKNIX often stores the new launcher on SD2/Ports but keeps the 174 MB
# original WPE runtime on SD1/tools. The two roots must be independent.
runtime_root=""
for root in "${FIRE4NIX_RUNTIME_ROOT:-}" "$bin_root" "${FIRE4NIX_ROOT:-}" \
  "$HERE/Fire4Nix" "$HERE" "$HERE/fire4nix-completo" \
  /storage/games-internal/roms/ports/fire4nix-completo \
  /storage/games-external/roms/ports/fire4nix-completo \
  /storage/roms/ports/fire4nix-completo \
  /storage/games-internal/roms/tools/Fire4Nix \
  /storage/games-external/roms/tools/Fire4Nix \
  /storage/roms/tools/Fire4Nix; do
  [ -n "$root" ] && [ -d "$root" ] || continue
  if [ -s "$root/runtime/lib/libWPEWebKit-2.0.so.1" ]; then
    runtime_root=$root
    break
  fi
done
selected=""
if [ -n "$bin_root" ] && [ -n "$runtime_root" ]; then selected=$bin_root; fi
{
  echo 'Fire4Nix 1.07 / WPE 139 investigation'
  printf 'mode=%s\n' "$MODE"
  printf 'arch=%s\n' "$(uname -m)"
  printf 'kernel=%s\n' "$(uname -r)"
  printf 'installed_root=%s\n' "${bin_root:-not_found}"
  printf 'wpe_runtime_root=%s\n' "${runtime_root:-not_found}"
  printf 'report_directory=%s\n' "$REPORT_DIR"
  # The historical backup contains an x86-64 ELF named fire4nix; it can
  # never run on the AArch64 R36H. Keep checks static in --safe mode.
  binary_arch=unknown
  wpe_arch=unknown
  if command -v readelf >/dev/null 2>&1; then
    if [ -n "$bin_root" ]; then
      machine=$(readelf -h "$bin_root/bin/fire4nix-native-aarch64" 2>/dev/null | grep "Machine:" | head -n 1 || true)
      case "$machine" in *AArch64*) binary_arch=aarch64 ;; *X86-64*) binary_arch=x86_64 ;; esac
    fi
    if [ -n "$runtime_root" ]; then
      machine=$(readelf -h "$runtime_root/runtime/lib/libWPEWebKit-2.0.so.1" 2>/dev/null | grep "Machine:" | head -n 1 || true)
      case "$machine" in *AArch64*) wpe_arch=aarch64 ;; *X86-64*) wpe_arch=x86_64 ;; esac
    fi
  fi
  printf "binary_elf_arch=%s\nwpe_elf_arch=%s\n" "$binary_arch" "$wpe_arch"
  if [ -n "$runtime_root" ]; then
    for p in WPEWebProcess WPENetworkProcess WPEGPUProcess; do
      if [ -s "$runtime_root/runtime/libexec/wpe-webkit-2.0/$p" ]; then
        printf 'process_%s=present\n' "$p"
      else
        printf 'process_%s=missing\n' "$p"
      fi
    done
    if command -v readelf >/dev/null 2>&1; then
      readelf -d "$runtime_root/runtime/lib/libWPEWebKit-2.0.so.1" 2>/dev/null |
        grep -E 'NEEDED|RUNPATH|RPATH' | tail -n 25 | cut -c 1-160 || true
    fi
    for lib in libc.so.6 ld-linux-aarch64.so.1 libwayland-client.so.0 \
       libgbm.so.1 libdrm.so.2 libEGL.so.1 libGLESv2.so.2 libmali.so; do
      if [ -e "$runtime_root/runtime/lib/$lib" ]; then
        printf 'private_system_gpu_library=%s\n' "$lib"
      fi
    done
  else
    if [ -z "$bin_root" ]; then echo 'result=missing_native_binary'; fi
    if [ -z "$runtime_root" ]; then echo 'result=missing_webkit_runtime'; fi
  fi
} > "$REPORT"

DIAG="$HERE/Diagnosticar-Fire4Nix.sh"
[ -f "$DIAG" ] || DIAG="$HERE/Fire4Nix/Diagnosticar-Fire4Nix.sh"
[ -f "$DIAG" ] || DIAG="${selected:-/nonexistent}/Diagnosticar-Fire4Nix.sh"
if [ -f "$DIAG" ]; then
  if [ -n "$runtime_root" ]; then
    FIRE4NIX_DIAGNOSTIC_RUNTIME="$runtime_root/runtime" \
    FIRE4NIX_DIAGNOSTIC_OUT="$REPORT_DIR/Fire4Nix-139-estatico.txt" \
      sh "$DIAG" --safe > "$RUN_DIR/static-output.txt" 2>&1
  else
    FIRE4NIX_DIAGNOSTIC_OUT="$REPORT_DIR/Fire4Nix-139-estatico.txt" \
      sh "$DIAG" --safe > "$RUN_DIR/static-output.txt" 2>&1
  fi
  printf 'static_diagnostic_exit=%s\n' "$?" >> "$REPORT"
  if [ -r "$REPORT_DIR/Fire4Nix-139-estatico.txt" ]; then
    grep -E '^(WPE_library=|WPE_runtime_source=|wpe_elf_arch=|wpe_glibc_max_required=|wpeplatform_static_symbol=|wpe_direct_glibc_compat=|wayland_socket=|fontconfig_fonts=|WPEPlatform_preflight=)' \
      "$REPORT_DIR/Fire4Nix-139-estatico.txt" >> "$REPORT" || true
  fi
else
  echo 'static_diagnostic=not_available' >> "$REPORT"
fi

if [ "$MODE" = --trace ] && [ "$(uname -m)" = aarch64 ] &&
   { [ "$binary_arch" = x86_64 ] || [ "$wpe_arch" = x86_64 ]; }; then
  echo "trace=skipped_wrong_arch_elf_not_AArch64" >> "$REPORT"
elif [ "$MODE" = --trace ] && [ -n "$selected" ]; then
  echo 'trace=starting_native_ABI_preflight_no_network_no_browser_window' >> "$REPORT"
  printf 'selected_binary=%s\nselected_runtime=%s\n' "$bin_root" "$runtime_root" >> "$REPORT"
  ulimit -c 0 2>/dev/null || true
  # Run the ELF directly: the installed SD may contain a 1.01/1.03 launcher
  # without the new isolated library policy or LD_DEBUG support.
  # ROCKNIX owns GPU/Mali variables and LD_PRELOAD; we never change them.
  LD_LIBRARY_PATH="$runtime_root/runtime/lib" \
    WEBKIT_EXEC_PATH="$runtime_root/runtime/libexec/wpe-webkit-2.0" \
    WPE_PLATFORM=wayland LD_DEBUG=libs,versions,files \
    LD_DEBUG_OUTPUT="$RUN_DIR/Fire4Nix-LD" \
    "$bin_root/bin/fire4nix-native-aarch64" --check-platform \
    > "$RUN_DIR/native-output.txt" 2>&1
  status=$?
  printf 'native_preflight_exit=%s\n' "$status" >> "$REPORT"
  if [ -r "$RUN_DIR/native-output.txt" ]; then
    if grep -Fq '[FIRE4NIX-NATIVE] dlopen success' "$RUN_DIR/native-output.txt"; then
      echo 'crash_boundary=after_dlopen' >> "$REPORT"
    elif grep -Fq '[FIRE4NIX-NATIVE] dlopen libWPEWebKit' "$RUN_DIR/native-output.txt"; then
      echo 'crash_boundary=during_dlopen_or_dependencies' >> "$REPORT"
    else
      echo 'crash_boundary=before_first_native_checkpoint_or_unknown' >> "$REPORT"
    fi
    grep -E '\[FIRE4NIX-(NATIVE|ABI)\]|library_path_mode=|warning=|loader error' \
      "$RUN_DIR/native-output.txt" | tail -n 32 | cut -c 1-170 >> "$REPORT" || true
  fi
  echo 'loader_last_relevant_lines_begin' >> "$REPORT"
  for trace in "$RUN_DIR"/Fire4Nix-LD-*; do
    [ -f "$trace" ] || continue
    grep -E 'libWPE|libwayland|libEGL|libGLES|libgbm|libdrm|libmali|calling init:|version .*not found|undefined symbol|error:' \
      "$trace" | tail -n 35 | cut -c 1-170 >> "$REPORT" || true
  done
  echo 'loader_last_relevant_lines_end' >> "$REPORT"
  printf 'raw_trace_dir=%s\n' "$RUN_DIR" >> "$REPORT"
elif [ "$MODE" = --trace ]; then
  echo 'trace=skipped_missing_binary_or_runtime' >> "$REPORT"
elif [ "$MODE" = --safe ]; then
  echo 'native_preflight=NOT_RUN_SAFE_MODE' >> "$REPORT"
fi
echo 'privacy=offline_no_websites_no_passwords_no_firmware_changes' >> "$REPORT"
echo 'hardware_browser_rendering=NOT_VERIFIED' >> "$REPORT"
echo 'END' >> "$REPORT"
cat "$REPORT"
echo "Relatorio salvo: $REPORT"
exit 0
