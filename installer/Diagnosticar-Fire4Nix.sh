#!/bin/sh
# Fire4Nix 1.01: inspect the actual SD card runtime without starting the GUI.
# Privacy: only file presence, ELF dependencies and controlled exit codes.
set -u
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 2
SCREEN=0
SAFE=0
case "${1:-}" in
  --screen) SCREEN=1 ;;
  --safe) SCREEN=1; SAFE=1 ;;
  "") ;;
  *) echo "Usage: sh Diagnosticar-Fire4Nix.sh [--screen|--safe]" >&2; exit 2 ;;
esac
ROOT="$HERE/Fire4Nix"
[ -s "$ROOT/bin/fire4nix-native-aarch64" ] || ROOT="$HERE"
# The downloaded ZIP may live on the second SD card. Check an installed copy.
if [ ! -s "$ROOT/bin/fire4nix-native-aarch64" ]; then
  for d in /storage/games-internal/roms/ports/fire4nix-completo \
           /storage/games-external/roms/ports/fire4nix-completo \
           /storage/roms/ports/fire4nix-completo; do
    if [ -s "$d/bin/fire4nix-native-aarch64" ]; then ROOT="$d"; break; fi
  done
fi
# An explicit runtime is useful for harmless mock tests and unusual SD layouts.
RUNTIME=""
for candidate in "${FIRE4NIX_DIAGNOSTIC_RUNTIME:-}" \
 "$ROOT/runtime" "$HERE/Fire4Nix/runtime" \
 "${FIRE4NIX_ROMS:-/no-roms}/tools/Fire4Nix/runtime" \
 "${FIRE4NIX_ROMS:-/no-roms}/ports/fire4nix-completo/runtime" \
 /storage/games-internal/roms/tools/Fire4Nix/runtime \
 /storage/games-external/roms/tools/Fire4Nix/runtime \
 /storage/games-internal/roms/ports/fire4nix-completo/runtime \
 /storage/games-external/roms/ports/fire4nix-completo/runtime \
 /storage/roms/tools/Fire4Nix/runtime \
 /storage/roms/ports/fire4nix-completo/runtime; do
  if [ -n "$candidate" ] && [ -s "$candidate/lib/libWPEWebKit-2.0.so.1" ]; then
    RUNTIME="$candidate"
    break
  fi
done
OUT=${FIRE4NIX_DIAGNOSTIC_OUT:-}
if [ -z "$OUT" ]; then
  if [ -d /storage ] && [ -w /storage ]; then
    OUT=/storage/Fire4Nix-Diagnostico-103.txt
  else
    OUT="$HERE/Fire4Nix-Diagnostico-103.txt"
  fi
fi
# Keep the report even if /storage cannot be written, and never clobber it midway.
DIR=$(dirname "$OUT")
if ! mkdir -p "$DIR" 2>/dev/null; then
  echo "Fire4Nix: cannot create output directory $DIR" >&2
  exit 73
fi
TMP=$(mktemp "$DIR/.fire4nix-diag-XXXXXX") || exit 73
trap 'rm -f "$TMP"' 0
{
  echo "Fire4Nix 1.03 / R36H standalone runtime diagnosis"
  printf 'arch=%s\n' "$(uname -m)"
  printf 'kernel=%s\n' "$(uname -r)"
  if [ -r /etc/os-release ]; then
    grep -E '^(NAME|VERSION_ID)=' /etc/os-release | head -n 2 || true
  fi
  printf 'installed_root=%s\n' "$ROOT"
  if command -v getconf >/dev/null 2>&1; then
    getconf GNU_LIBC_VERSION 2>/dev/null || true
  fi
  if [ -r /proc/meminfo ]; then
    grep -E '^(MemTotal|MemAvailable):' /proc/meminfo || true
  fi
  BIN="$ROOT/bin/fire4nix-native-aarch64"
  if [ -s "$BIN" ]; then echo 'arm64_binary=present'; else echo 'arm64_binary=missing'; fi
  # Static/pre-launch environment inspection recommended by WPE upstream.
  # These warnings indicate missing prerequisites, not the cause of a 139.
  if command -v fc-list >/dev/null 2>&1; then
    font_sample=$(fc-list -f '%{file}\n' 2>/dev/null | sed -n '/./{p;q;}' || true)
    if [ -n "$font_sample" ] && [ -r "$font_sample" ]; then
      echo 'fontconfig_fonts=present'
    else
      echo 'fontconfig_fonts=none_found'
    fi
  else
    # ROCKNIX fontconfig package deliberately removes /usr/bin utilities.
    # Missing fc-list is NOT evidence of missing fallback font files.
    font_file=$(find /usr/share/fonts /storage/.fonts /storage/.local/share/fonts \
       -type f \( -iname '*.ttf' -o -iname '*.otf' -o -iname '*.ttc' \) \
       -print -quit 2>/dev/null || true)
    if [ -n "$font_file" ]; then
      echo 'fontconfig_fonts=files_present_cache_unverified'
    else
      echo 'fontconfig_fonts=tool_missing_no_known_font_files'
    fi
  fi
  if [ -r /usr/share/mime/globs2 ] || [ -r /usr/share/mime/mime.cache ]; then
    echo 'shared_mime_database=present'
  else
    echo 'shared_mime_database=not_found_local_HTML_may_fail'
  fi
  if command -v bwrap >/dev/null 2>&1; then
    echo 'bubblewrap=present_in_PATH'
  else
    echo 'bubblewrap=missing_from_PATH_sandbox_unverified'
  fi
  if [ -n "$RUNTIME" ]; then
    for name in libc.so.6 libm.so.6 libpthread.so.0 ld-linux-aarch64.so.1 libEGL.so.1 libGLESv2.so.2 libgbm.so.1 libdrm.so.2 libwayland-client.so.0; do
      if [ -e "$RUNTIME/lib/$name" ]; then
        printf 'private_library_conflict_candidate=%s\n' "$name"
      fi
    done
    if [ -r "$RUNTIME/lib/libWPEWebKit-2.0.so.1" ]; then
      echo 'webkit_process_path_override=build_dependent_unverified'
    fi
  fi
  if command -v getconf >/dev/null 2>&1; then
    device_glibc=$(getconf GNU_LIBC_VERSION 2>/dev/null | awk '{print $NF}' || true)
    printf 'device_glibc=%s\n' "${device_glibc:-unknown}"
  fi
  if [ -n "$RUNTIME" ]; then
    echo "WPE_library=present"
    printf 'WPE_runtime_source=%s\n' "$RUNTIME"
    if command -v stat >/dev/null 2>&1; then
      stat -c 'WPE_library_bytes=%s' "$RUNTIME/lib/libWPEWebKit-2.0.so.1" 2>/dev/null || true
    fi
  else
    echo 'WPE_library=missing'
    echo 'WPE_runtime_source=not_found_on_checked_SD_paths'
  fi
  # Report whether GPUProcess is REQUIRED, not simply whether it exists.
  # The launcher and installer accept GPU-off only with a verified local
  # ROCKNIX Wayland profile; unknown/ambiguous reports never waive a process.
  gpu_required=1
  gpu_profile_state=legacy_requires_gpu
  if [ -z "$RUNTIME" ]; then
    gpu_profile_state=no_runtime
  else
    gpu_report="$RUNTIME/BUILD-REPORT.txt"
    if [ -e "$gpu_report" ] || [ -L "$gpu_report" ]; then
      if [ ! -f "$gpu_report" ] || [ -L "$gpu_report" ]; then
        gpu_profile_state=invalid_report_requires_gpu
      else
        gpu_evidence=$(sed -n 's/^GPU_PROCESS_PROFILE=//p' "$gpu_report") || gpu_evidence=invalid
        case "$gpu_evidence" in
          disabled_verified_wayland)
            gpu_required=0
            gpu_profile_state=disabled_verified_wayland ;;
          required_unverified|enabled_verified|'')
            gpu_profile_state=requires_gpu ;;
          *) gpu_profile_state=invalid_report_requires_gpu ;;
        esac
      fi
    fi
  fi
  printf 'gpu_runtime_profile=%s\n' "$gpu_profile_state"
  printf 'gpu_process_required=%s\n' "$gpu_required"
  for process in WPEWebProcess WPENetworkProcess WPEGPUProcess; do
    if [ -n "$RUNTIME" ] && [ -s "$RUNTIME/libexec/wpe-webkit-2.0/$process" ]; then
      printf '%s=present\n' "$process"
    elif [ "$process" = WPEGPUProcess ] && [ "$gpu_required" -eq 0 ]; then
      echo 'WPEGPUProcess=not_required_verified_wayland'
    else
      printf '%s=missing\n' "$process"
    fi
  done
  if [ "$SAFE" -eq 1 ]; then
    echo 'WPE_dynamic_dependencies=skipped_in_safe_mode_no_loader'
  elif [ -n "$RUNTIME" ] && command -v ldd >/dev/null 2>&1; then
    echo 'WPE_missing_dynamic_dependencies_begin'
    LD_LIBRARY_PATH="$RUNTIME/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
      ldd "$RUNTIME/lib/libWPEWebKit-2.0.so.1" 2>/dev/null |
      awk '/=> not found/ { print $1 "=not_found" }' || true
    echo 'WPE_missing_dynamic_dependencies_end'
  else
    echo 'WPE_dynamic_dependencies=not_examined'
  fi
  printf 'wayland_display=%s\n' "${WAYLAND_DISPLAY:-unset}"
  printf 'wayland_runtime_dir=%s\n' "${XDG_RUNTIME_DIR:-unset}"
  if [ -S "${XDG_RUNTIME_DIR:-/none}/${WAYLAND_DISPLAY:-missing}" ]; then
    echo 'wayland_socket=present'
  else
    echo 'wayland_socket=not_confirmed'
    for root in /var/run/0-runtime-dir /run/user/0; do
      for socket in wayland-1 wayland-0; do
        if [ -S "$root/$socket" ]; then echo 'alternate_wayland_socket=present'; fi
      done
    done
  fi
  if [ -e /dev/dri/renderD128 ]; then echo 'drm_render_node=present'
  elif [ -d /dev/dri ]; then echo 'drm_render_node=not_confirmed'
  else echo 'drm_render_node=directory_missing'; fi
  if [ -s "$ROOT/config/fire4nix.gptk" ]; then
    echo 'gamepad_profile=present'
  else echo 'gamepad_profile=missing'; fi
  if command -v gptokeyb >/dev/null 2>&1 ||
      [ -x /usr/bin/gptokeyb ]; then
    echo 'gptokeyb=detected'
  else echo 'gptokeyb=not_detected'; fi
  if [ -e /dev/uinput ] && [ -w /dev/uinput ]; then echo 'uinput=writable'
  elif [ -e /dev/uinput ]; then echo 'uinput=restricted'
  else echo 'uinput=not_detected'; fi
  if [ -n "$RUNTIME" ]; then
    if command -v readelf >/dev/null 2>&1; then
      echo 'elf_static_inspection=readelf'
      if readelf -h "$RUNTIME/lib/libWPEWebKit-2.0.so.1" 2>/dev/null | grep -q 'Machine:.*AArch64'; then
        echo 'wpe_elf_arch=AArch64'
      else
        echo 'wpe_elf_arch=unexpected_or_unreadable'
      fi
      # ELF symbol version requirements help compare an externally built WPE
      # against the device's actual glibc 2.41 (not the GitHub tree's version).
      max_required=$(readelf --version-info "$RUNTIME/lib/libWPEWebKit-2.0.so.1" 2>/dev/null |
        grep -o 'Name: GLIBC_[0-9][0-9.]*' |
        sed 's/^Name: GLIBC_//' | sort -V | tail -n 1 || true)
      printf 'wpe_glibc_max_required=%s\n' "${max_required:-not_available}"
      # This compares only the top-level WPE library; transitive dependencies
      # may still require newer GLIBC and must be evaluated separately.
      if [ -n "${device_glibc:-}" ] && [ -n "$max_required" ]; then
        latest_glibc=$(printf '%s\n%s\n' "$device_glibc" "$max_required" | sort -V | tail -n 1)
        if [ "$latest_glibc" = "$max_required" ] && [ "$max_required" != "$device_glibc" ]; then
          echo 'wpe_direct_glibc_compat=requires_newer_than_device'
        else
          echo 'wpe_direct_glibc_compat=direct_library_requirement_not_newer'
        fi
      else
        echo 'wpe_direct_glibc_compat=unknown'
      fi
      if readelf --dyn-syms -W "$RUNTIME/lib/libWPEWebKit-2.0.so.1" 2>/dev/null |
          grep -q 'webkit_web_view_get_wpe_view'; then
        echo 'wpeplatform_static_symbol=present'
      else
        echo 'wpeplatform_static_symbol=absent_or_unreadable'
      fi
    else
      echo 'elf_static_inspection=readelf_unavailable'
    fi
  fi
  if [ "$SAFE" -eq 1 ]; then
    echo 'WPEPlatform_preflight=skipped_safe_mode_no_library_execution'
    echo 'SAFE_MODE_NOTE=readelf_only_without_ldd_or_WPE_execution'
  elif [ -s "$BIN" ] && [ -n "$RUNTIME" ]; then
    # Disable dumps of large WebKit process images after a suspected SIGSEGV.
    # Preserve exact stderr and native stage checkpoints for photographs.
    ulimit -c 0 2>/dev/null || true
    # Run only the ABI check, NOT a window or a webpage. It is valid even
    # when the new ZIP is on SD2 and the runtime is still on SD1.
    LD_LIBRARY_PATH="$RUNTIME/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
       WEBKIT_EXEC_PATH="$RUNTIME/libexec/wpe-webkit-2.0" \
       "$BIN" --check-platform > "$TMP.abi" 2>&1
    result=$?
    printf 'WPEPlatform_preflight_exit=%s\n' "$result"
    if [ "$result" -eq 139 ]; then
      echo 'WPEPlatform_fault=SIGSEGV_in_preflight'
      if grep -Fq '[FIRE4NIX-NATIVE] dlopen success' "$TMP.abi"; then
        echo 'WPEPlatform_fault_stage=after_dlopen_success'
      elif grep -Fq '[FIRE4NIX-NATIVE] dlopen libWPEWebKit' "$TMP.abi"; then
        echo 'WPEPlatform_fault_stage=during_dlopen_or_its_dependencies'
      else
        echo 'WPEPlatform_fault_stage=before_first_native_checkpoint_or_unknown'
      fi
    fi
    echo 'WPEPlatform_native_checkpoints_begin'
    grep -F '[FIRE4NIX-NATIVE]' "$TMP.abi" | tail -n 12 | cut -c 1-140 || true
    echo 'WPEPlatform_native_checkpoints_end'
    echo 'WPEPlatform_loader_messages_begin'
    grep -E '(^| )(error|Error|Segmentation fault|undefined symbol|version .*not found|cannot open)' "$TMP.abi" |
      tail -n 8 | cut -c 1-160 || true
    echo 'WPEPlatform_loader_messages_end'
    awk -F= '/^\[FIRE4NIX-ABI\] wpe_version=/ { print "WPE_version=" $2 }' "$TMP.abi" | head -n 1
    grep '^\[FIRE4NIX-ABI\]' "$TMP.abi" | head -n 17 || true
    case "$result" in
      0) echo 'WPEPlatform_preflight_note=ABI_present_not_graphics_test' ;;
      78) echo 'WPEPlatform_preflight_note=legacy_library_without_new_API' ;;
      127) echo 'WPEPlatform_preflight_note=dynamic_loader_or_symbol_missing' ;;
      *) echo 'WPEPlatform_preflight_note=inspect_loader_or_abi_logs' ;;
    esac
    rm -f "$TMP.abi"
  elif [ -s "$BIN" ] && [ -f "$ROOT/Fire4Nix-Iniciar.sh" ]; then
    sh "$ROOT/Fire4Nix-Iniciar.sh" --check-platform >/dev/null 2>&1
    printf 'WPEPlatform_preflight_exit=%s\n' "$?"
    echo 'WPEPlatform_preflight_note=no_local_runtime_found'
  elif [ -s "$BIN" ]; then
    echo 'WPEPlatform_preflight=skipped_runtime_missing_no_launcher'
  else
    echo 'WPEPlatform_preflight=skipped_missing_binary'
  fi
  echo 'DIAGNOSTIC_NOTE=no_network_no_passwords_no_personal_files'
  echo 'GRAPHICS_STATUS=NOT_VERIFIED_BY_PREFLIGHT'
  echo END
} > "$TMP" 2>&1
mv -f "$TMP" "$OUT" || exit 73
trap - 0
echo "Fire4Nix full diagnosis: $OUT"
if [ "$SCREEN" -eq 1 ]; then
  echo '=== FIRE4NIX 1.03 / RESUMO PARA FOTO ==='
  grep -E '^(arch=|WPE_library=|WPE_runtime_source=|WPEWebProcess=|WPENetworkProcess=|WPEGPUProcess=|gpu_runtime_profile=|gpu_process_required=|WPE_version=|WPEPlatform_fault_stage=|WPEPlatform_fault=|wpe_elf_arch=|wpe_glibc_max_required=|wpe_direct_glibc_compat=|fontconfig_fonts=|shared_mime_database=|bubblewrap=|private_library_conflict_candidate=|wpeplatform_static_symbol=|WPEPlatform_preflight=|WPEPlatform_preflight_exit=|WPEPlatform_preflight_note=|wayland_socket=|alternate_wayland_socket=|drm_render_node=|gptokeyb=|uinput=|GRAPHICS_STATUS=)' "$OUT" |
    cut -c 1-100
  echo '=== FIM DO RESUMO ==='
fi
