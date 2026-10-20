#!/bin/sh
# Fire4Nix R36H: read-only GStreamer ELF ABI check; never dlopen, download or modify firmware.
# Usage: sh audit-wpe-gstreamer.sh [--audit|--strict] [runtime-root]
set -u
MODE=${1:---audit}
case "$MODE" in --audit|--strict) ;; *) echo "Usage: $0 [--audit|--strict] [runtime-root]" >&2; exit 2 ;; esac
ROOT=${2:-${FIRE4NIX_WPE_ROOT:-/storage/games-external/roms/ports/Fire4Nix-RK3326-Resgate/Fire4Nix/runtime/aarch64}}
case "$ROOT" in */lib) LIB=$ROOT ;; *) LIB=$ROOT/lib ;; esac
[ -d "$LIB" ] || { echo "ERROR: no lib directory: $LIB" >&2; exit 2; }
command -v readelf >/dev/null 2>&1 || { echo 'ERROR: readelf required' >&2; exit 2; }
REPORT=${FIRE4NIX_GST_REPORT:-}
if [ -z "$REPORT" ]; then
  if [ -d /storage ] && [ -w /storage ]; then REPORT=/storage/Fire4Nix-GStreamer-Auditoria.txt
  else REPORT=/tmp/Fire4Nix-GStreamer-Auditoria-$$.txt; fi
fi
TMP=$REPORT.tmp.$$
trap 'rm -f "$TMP"' 0 HUP INT TERM
: > "$TMP" || { echo "ERROR: cannot write $TMP" >&2; exit 2; }
checked=0
broken=0
wpe=missing
if [ -f "$LIB/libWPEWebKit-2.0.so.1" ]; then
  if readelf -h "$LIB/libWPEWebKit-2.0.so.1" 2>/dev/null | grep -q 'Machine:.*AArch64'; then wpe=aarch64_elf
  else wpe=invalid_or_other_arch; fi
fi
{
  echo "Fire4Nix GStreamer static ABI audit v1"
  echo "mode=$MODE"
  echo "libdir=$LIB"
  echo "webkit=$wpe"
  echo "device_arch=$(uname -m 2>/dev/null || echo unknown)"
  echo "device_glibc=$(getconf GNU_LIBC_VERSION 2>/dev/null || echo unknown)"
  for core in libgstreamer-1.0.so.0 libgstbase-1.0.so.0; do
    if [ -e "$LIB/$core" ]; then echo "private_core_$core=present"
    else echo "private_core_$core=not_bundled_(may_use_system)"; fi
  done
  if [ -e /usr/lib/compat/libxml2.so.2 ]; then echo 'rocknix_xml2_compat=present'; fi
  if [ -e /usr/lib/gl4es/libGL.so.1 ]; then echo 'rocknix_gl4es=present'; fi
  for f in "$LIB"/libgst*.so "$LIB"/libgst*.so.*; do
    [ -f "$f" ] || continue
    [ -L "$f" ] && continue
    checked=$((checked+1))
    name=${f##*/}
    echo "LIBRARY=$name"
    if ! readelf -h "$f" >/dev/null 2>&1; then
      echo "BROKEN_ELF=$name"
      broken=$((broken+1))
      continue
    fi
    echo "NEEDED_BEGIN=$name"
    readelf -d "$f" 2>/dev/null | grep NEEDED | sed -n '1,30p' || true
    echo "NEEDED_END=$name"
    # GST_CAT_DEFAULT is usually defined by the module, not libgstreamer API.
    if readelf -W --dyn-syms "$f" 2>/dev/null | grep -E 'UND[[:space:]]+GST_CAT_DEFAULT([[:space:]]|$)' >/dev/null; then
      echo "UNRESOLVED_GST_CAT_DEFAULT=$name"
      broken=$((broken+1))
    fi
  done
  echo "gst_libraries_checked=$checked"
  echo "gst_libraries_with_findings=$broken"
  if [ "$broken" -gt 0 ]; then
    echo 'status=BLOCK_GST_ABI'
    echo 'reason=undefined_GST_CAT_DEFAULT_or_invalid_ELF'
    echo 'action=rebuild_GStreamer_consistently_or_rebuild_WPE_without_multimedia_dependencies'
  elif [ "$checked" -eq 0 ]; then
    echo 'status=NO_BUNDLED_GSTREAMER_FOUND'
    echo 'note=does_not_prove_transitive_dependencies_available'
  else
    echo 'status=STATIC_GST_SYMBOL_CHECK_PASS'
    echo 'note=does_not_prove_full_compatibility_or_rendering'
  fi
  echo 'wpe_executed=no'
  echo 'system_modified=no'
} >> "$TMP" 2>&1
mv "$TMP" "$REPORT" || exit 2
cat "$REPORT"
echo "REPORT=$REPORT"
if [ "$MODE" = --strict ] && [ "$broken" -gt 0 ]; then exit 6; fi
exit 0
