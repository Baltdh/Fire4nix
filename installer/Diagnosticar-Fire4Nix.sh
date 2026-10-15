#!/bin/sh
# Fire4Nix 0.93: device-local, privacy-minimal diagnostics. No network/firmware writes.
set -u
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 2
ROOT="$HERE/Fire4Nix"
[ -d "$ROOT" ] || ROOT="$HERE"
if [ ! -f "$ROOT/bin/fire4nix-native-aarch64" ]; then
  for d in /storage/games-internal/roms/ports/fire4nix-completo /storage/games-external/roms/ports/fire4nix-completo /storage/roms/ports/fire4nix-completo; do
    if [ -f "$d/bin/fire4nix-native-aarch64" ]; then ROOT="$d"; break; fi
  done
fi
OUT=${FIRE4NIX_DIAGNOSTIC_OUT:-}
if [ -z "$OUT" ]; then
    if [ -d /storage ] && [ -w /storage ]; then
        OUT=/storage/Fire4Nix-Diagnostico-093.txt
    else
        OUT="$HERE/Fire4Nix-Diagnostico-093.txt"
    fi
fi
TMP="$OUT.$$"
if ! ( : > "$TMP" ) 2>/dev/null; then
    echo "Fire4Nix: cannot write diagnostic to $OUT" >&2
    exit 73
fi
trap 'rm -f "$TMP" 2>/dev/null || true' 0
{
  echo "Fire4Nix 0.93 / R36H diagnostic"
  date '+datetime=%Y-%m-%d %H:%M:%S %z' 2>/dev/null || true
  printf 'arm=%s kernel=%s\n' "$(uname -m 2>/dev/null)" "$(uname -r 2>/dev/null)"
  if [ -r /etc/os-release ]; then
      grep -E '^(PRETTY_NAME|VERSION_ID|NAME)=' /etc/os-release | head -n 3 || true
  fi
  if command -v getconf >/dev/null 2>&1; then
      getconf GNU_LIBC_VERSION 2>/dev/null || true
  fi
  if [ -r /proc/meminfo ]; then
      grep -E '^(MemTotal|MemAvailable):' /proc/meminfo || true
  fi
  printf 'installed_root=%s\n' "$ROOT"
  BIN="$ROOT/bin/fire4nix-native-aarch64"
  if [ -s "$BIN" ]; then
      echo "arm64_binary=present"
      if command -v file >/dev/null 2>&1; then file "$BIN" 2>/dev/null || true; fi
  else
      echo "arm64_binary=missing"
  fi
  LIB="$ROOT/runtime/lib/libWPEWebKit-2.0.so.1"
  if [ -s "$LIB" ]; then
      echo "WPE_library=present"
      if command -v stat >/dev/null 2>&1; then
          stat -c 'WPE_library_bytes=%s' "$LIB" 2>/dev/null || true
      fi
  else
      echo "WPE_library=missing"
  fi
  for process in WPEWebProcess WPENetworkProcess WPEGPUProcess; do
      if [ -s "$ROOT/runtime/libexec/wpe-webkit-2.0/$process" ]; then
          printf '%s=present\n' "$process"
      else
          printf '%s=missing\n' "$process"
      fi
  done
  printf 'session_wayland=%s\nsession_dir=%s\n' "${WAYLAND_DISPLAY:-unset}" "${XDG_RUNTIME_DIR:-unset}"
  for dir in "${XDG_RUNTIME_DIR:-/no-runtime}" /var/run/0-runtime-dir /run/user/0; do
      for name in wayland-1 wayland-0; do
          [ ! -S "$dir/$name" ] || printf 'wayland_socket=found:%s/%s\n' "$dir" "$name"
      done
  done
  if [ -d /dev/dri ]; then
      for node in /dev/dri/renderD* /dev/dri/card*; do
          [ ! -e "$node" ] || printf 'drm_node=%s\n' "$node"
      done
  else
      echo "drm_directory=missing"
  fi
  if [ -r /proc/modules ]; then
      grep -E '^(panfrost|mali|rockchipdrm|drm) ' /proc/modules | cut -d ' ' -f 1 || true
  fi
  if [ -f "$ROOT/Fire4Nix-Iniciar.sh" ] && [ -f "$BIN" ]; then
      echo "WPEPlatform_preflight_begin"
      sh "$ROOT/Fire4Nix-Iniciar.sh" --check-platform >/dev/null 2>&1
      result=$?
      printf 'WPEPlatform_preflight_exit=%s\n' "$result"
      case "$result" in
        0) echo "WPEPlatform_preflight_note=symbols_found_only_no_graphics_test" ;;
        78) echo "WPEPlatform_preflight_note=legacy_API_missing" ;;
        127) echo "WPEPlatform_preflight_note=runtime_or_loader_missing" ;;
        *) echo "WPEPlatform_preflight_note=inspect_launcher_log" ;;
      esac
  else
      echo "WPEPlatform_preflight=skipped_missing_launcher_or_binary"
  fi
  echo "NOTE: no MAC addresses, network identifiers, passwords or Terminal R36 logs collected"
  echo "END"
} > "$TMP" 2>&1
mv -f "$TMP" "$OUT" || exit 73
trap - 0
printf 'Fire4Nix diagnostic saved: %s\n' "$OUT"
