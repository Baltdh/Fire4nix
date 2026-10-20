#!/bin/sh
# Fire4Nix 1.15 - R36H read-only physical test after exFAT corruption.
# NEVER runs WebKit, fsck, repair, downloads, chmod or firmware writes.
set -u
case "${1:---safe}" in
  --safe) ;;
  --help) echo 'sh Fire4Nix-R36H-Teste-Seguro.sh --safe'; echo 'Only writes a small report to /tmp'; exit 0 ;;
  *) echo 'ERROR: use --safe or --help' >&2; exit 2 ;;
esac
umask 077
TMPBASE=${FIRE4NIX_SAFE_TMPDIR:-${TMPDIR:-/tmp}}
[ -d "$TMPBASE" ] && [ -w "$TMPBASE" ] || { echo 'ERROR: no writable temporary directory (no SD fallback)' >&2; exit 73; }
REPORT=$(mktemp "$TMPBASE/Fire4Nix-Seguro-XXXXXX.txt") || exit 73
log() { printf '%s\n' "$*" >> "$REPORT"; }
log 'FIRE4NIX_R36H_TESTE=1.15'
log 'test_mode=STATIC_READ_ONLY'
log 'web_browser_executed=no'
log 'system_modified=no'
log "arch=$(uname -m 2>/dev/null || echo unknown)"
log "kernel=$(uname -r 2>/dev/null || echo unknown)"
if command -v getconf >/dev/null 2>&1; then log "glibc=$(getconf GNU_LIBC_VERSION 2>/dev/null || echo unknown)"; fi
if [ -r /proc/meminfo ]; then
  sed -n 's/^MemAvailable:[[:space:]]*/memory_available=/p' /proc/meminfo | head -n 1 >> "$REPORT"
fi
if [ -r /proc/mounts ]; then
  awk '($2=="/storage/roms" || $2=="/storage/games-external" || $2=="/storage/games-internal" || $2=="/storage") {print "mount=" $2 " fs=" $3 " device=" $1}' /proc/mounts >> "$REPORT"
fi
if command -v dmesg >/dev/null 2>&1 &&
   dmesg 2>/dev/null | grep -Eiq 'exFAT-fs .*Volume was not properly unmounted|exFAT-fs .*Some data may be corrupt'; then
  log 'external_sd_warning=EXFAT_UNCLEAN_UNMOUNT'
  log 'sd_action=BACKUP_AND_OFFLINE_FSCK_AFTER_UNMOUNT'
else
  log 'external_sd_warning=NONE_IN_AVAILABLE_KERNEL_LOG'
  log 'sd_action=NO_FSCK_WAS_RUN'
fi
if [ -S "${XDG_RUNTIME_DIR:-/none}/${WAYLAND_DISPLAY:-invalid}" ]; then
  log 'wayland_socket=present'
else
  log 'wayland_socket=not_in_terminal_environment'
  alt=missing
  for dir in /var/run/0-runtime-dir /run/user/0; do
    for sock in wayland-0 wayland-1; do
      if [ -S "$dir/$sock" ]; then alt=present; break 2; fi
    done
  done
  log "alternate_wayland_socket=$alt"
fi
if [ -e /dev/dri/renderD128 ]; then log 'drm_render=present'; else log 'drm_render=not_found'; fi
if command -v gptokeyb >/dev/null 2>&1; then log 'gamepad_mapper=present'; else log 'gamepad_mapper=not_found'; fi
if command -v readelf >/dev/null 2>&1; then log 'readelf=present'; else log 'readelf=missing'; fi
RUNTIME=''
for d in "${FIRE4NIX_SAFE_RUNTIME:-}" \
 /storage/games-internal/roms/tools/Fire4Nix/runtime \
 /storage/games-internal/roms/ports/fire4nix-completo/runtime \
 /storage/games-external/roms/tools/Fire4Nix/runtime \
 /storage/games-external/roms/ports/fire4nix-completo/runtime \
 /storage/roms/tools/Fire4Nix/runtime \
 /storage/roms/ports/fire4nix-completo/runtime \
 /storage/games-external/roms/ports/Fire4Nix-RK3326-Resgate/Fire4Nix/runtime/aarch64; do
  [ -n "$d" ] || continue
  if [ -f "$d/lib/libWPEWebKit-2.0.so.1" ]; then RUNTIME="$d"; break; fi
done
if [ -z "$RUNTIME" ]; then
  log 'wpe_runtime=not_found'
  log 'test_result=NO_WPE_FOUND'
else
  log 'wpe_runtime=found'
  log "runtime_path=$RUNTIME"
  WPE="$RUNTIME/lib/libWPEWebKit-2.0.so.1"
  if command -v stat >/dev/null 2>&1; then
    log "webkit_bytes=$(stat -c %s "$WPE" 2>/dev/null || echo unknown)"
  fi
  if command -v readelf >/dev/null 2>&1; then
    if readelf -h "$WPE" 2>/dev/null | grep -q 'Machine:.*AArch64'; then
      log 'webkit_elf=VALID_AARCH64_HEADER'
    else
      log 'webkit_elf=BAD_HEADER_OR_NOT_AARCH64'
    fi
    if readelf -W --dyn-syms "$WPE" 2>/dev/null | grep -q 'webkit_web_view_get_wpe_view'; then
      log 'wpeplatform_symbol=present'
    else
      log 'wpeplatform_symbol=absent_or_unreadable'
    fi
  else
    log 'webkit_elf=NOT_CHECKED_NO_READELF'
  fi
  for proc in WPEWebProcess WPENetworkProcess WPEGPUProcess; do
    if [ -s "$RUNTIME/libexec/wpe-webkit-2.0/$proc" ]; then
      log "$proc=present"
    else
      log "$proc=missing"
    fi
  done
  GST="$RUNTIME/lib/libgstvideo-1.0.so.0"
  if [ -f "$GST" ] && command -v readelf >/dev/null 2>&1; then
    if readelf -W --dyn-syms "$GST" 2>/dev/null | grep -Eq 'UND[[:space:]]+GST_CAT_DEFAULT(@|[[:space:]]|$)'; then
      log 'gst_cat_default=UNDEFINED_SYMBOL_CONFIRMED'
      log 'runtime_action=DO_NOT_LAUNCH_OLD_WEBKIT'
    else
      log 'gst_cat_default=NOT_FOUND_IN_GSTVIDEO'
    fi
  else
    log 'gst_cat_default=NOT_CHECKED_NO_GSTVIDEO'
  fi
  if grep -Eq '^webkit_elf=BAD_HEADER|^gst_cat_default=UNDEFINED' "$REPORT"; then
    log 'test_result=BLOCKED_KNOWN_RUNTIME_ABI'
  else
    log 'test_result=STATIC_CHECK_ONLY_NO_BROWSER_EXECUTED'
  fi
fi
log 'note=No browser start, ZIP unpack, filesystem repair or network operations'
log 'END'
cat "$REPORT"
printf 'RELATORIO=%s\n' "$REPORT"
exit 0
