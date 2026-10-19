#!/bin/sh
# Fire4Nix R36H 1.08: read-only ELF/ABI diagnostic via ROCKNIX Ports.
# Never runs WebKit, ldd, downloads, or changes the firmware/installed library.
# Optional: FIRE4NIX_ELF_FILE=path FIRE4NIX_ELF_REPORT=path; --hash reads the whole file.
set -u
umask 077
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 2
MODE=${1:---quick}
case "$MODE" in --quick|--hash) ;; *) echo "Use: sh Fire4Nix-Inspecionar-ELF.sh [--quick|--hash]" >&2; exit 2 ;; esac

REPORT=${FIRE4NIX_ELF_REPORT:-}
if [ -z "$REPORT" ]; then
  if [ -d /storage ] && [ -w /storage ]; then
    REPORT=/storage/Fire4Nix-ELF-ultimo.txt
  else
    REPORT="$HERE/Fire4Nix-ELF-ultimo.txt"
  fi
fi
LIB=${FIRE4NIX_ELF_FILE:-}
if [ -z "$LIB" ]; then
  for file in \
    /storage/games-internal/roms/tools/Fire4Nix/runtime/lib/libWPEWebKit-2.0.so.1 \
    /storage/games-external/roms/tools/Fire4Nix/runtime/lib/libWPEWebKit-2.0.so.1 \
    /storage/roms/tools/Fire4Nix/runtime/lib/libWPEWebKit-2.0.so.1 \
    "$HERE/Fire4Nix/runtime/lib/libWPEWebKit-2.0.so.1" \
    "$HERE/runtime/lib/libWPEWebKit-2.0.so.1" \
    /storage/games-internal/roms/ports/fire4nix-completo/runtime/lib/libWPEWebKit-2.0.so.1 \
    /storage/games-external/roms/ports/fire4nix-completo/runtime/lib/libWPEWebKit-2.0.so.1 \
    /storage/roms/ports/fire4nix-completo/runtime/lib/libWPEWebKit-2.0.so.1
  do
    if [ -e "$file" ] || [ -L "$file" ]; then LIB=$file; break; fi
  done
fi

hex_prefix() {
  od -An -tx1 -N "$2" "$1" 2>/dev/null | tr -d ' \n'
}
identify() {
  case "$1" in
    7f454c46*) echo ELF_magic ;;
    1f8b*) echo gzip_not_ELF ;;
    fd377a585a00*) echo xz_not_ELF ;;
    28b52ffd*) echo zstd_not_ELF ;;
    504b0304*|504b0506*|504b0708*) echo zip_not_ELF ;;
    76657273696f6e2068747470733a2f2f6769742d6c6673*) echo git_lfs_pointer_not_ELF ;;
    3c68746d6c*|3c48544d4c*|3c21646f6374797065*|3c21444f4354595045*) echo html_not_ELF ;;
    00000000*) echo leading_zero_bytes_not_ELF ;;
    "") echo unreadable_or_empty ;;
    *) echo unknown_non_ELF ;;
  esac
}
record_elf() {
  path=$1
  label=$2
  if [ ! -e "$path" ]; then
    if [ -L "$path" ]; then echo "${label}_status=broken_symlink"; else echo "${label}_status=not_found"; fi
    return
  fi
  if [ ! -f "$path" ]; then echo "${label}_status=not_regular_file"; return; fi
  echo "${label}_status=present"
  echo "${label}_path=$path"
  if [ -L "$path" ]; then
    echo "${label}_symlink=yes"
    echo "${label}_link_target=$(readlink "$path" 2>/dev/null || echo unreadable)"
  else
    echo "${label}_symlink=no"
  fi
  if command -v stat >/dev/null 2>&1; then
    stat -Lc "${label}_size_bytes=%s" "$path" 2>/dev/null || true
    stat -Lc "${label}_blocks_512=%b" "$path" 2>/dev/null || true
    stat -Lc "${label}_hardlinks=%h" "$path" 2>/dev/null || true
  else
    wc -c < "$path" | awk -v p="$label" '{print p "_size_bytes=" $1}'
  fi
  if ! command -v od >/dev/null 2>&1; then
    echo "${label}_format=unknown_od_missing"
    return
  fi
  prefix=$(hex_prefix "$path" 64)
  magic=$(hex_prefix "$path" 4)
  echo "${label}_first_4_hex=$magic"
  echo "${label}_first_64_hex=$prefix"
  fmt=$(identify "$prefix")
  echo "${label}_format=$fmt"
  if [ "$magic" != 7f454c46 ]; then
    echo "${label}_verdict=BLOCK_NON_ELF"
    return
  fi
  if command -v readelf >/dev/null 2>&1; then
    echo "${label}_readelf_header_begin"
    readelf -h "$path" 2>&1 | sed -n '1,24p'
    echo "${label}_readelf_header_end"
    machine=$(readelf -h "$path" 2>/dev/null | grep 'Machine:' | head -n 1 || true)
    case "$machine" in
      *AArch64*) echo "${label}_architecture=aarch64";;
      *X86-64*) echo "${label}_architecture=x86_64_NOT_R36H";;
      *ARM*) echo "${label}_architecture=arm_other_check_ELF_class";;
      *) echo "${label}_architecture=unknown";;
    esac
    echo "${label}_dependencies_begin"
    readelf -d "$path" 2>/dev/null | grep -E 'NEEDED|RUNPATH|RPATH' | cut -c 1-170 | head -n 60 || true
    echo "${label}_dependencies_end"
    echo "${label}_glibc_symbols_begin"
    readelf -V "$path" 2>/dev/null | grep -o 'Name: GLIBC_[0-9.]*' | sort -Vu | tail -n 12 || true
    echo "${label}_glibc_symbols_end"
  else
    echo "${label}_readelf=unavailable"
  fi
  echo "${label}_verdict=ELF_MAGIC_PRESENT_OTHER_ABI_CHECKS_REQUIRED"
}
{
  echo 'Fire4Nix 1.08 - static ELF and runtime compatibility inspection'
  echo 'privacy=no_network_no_credentials_no_firmware_changes'
  echo "mode=$MODE"
  echo "device_arch=$(uname -m 2>/dev/null || echo unavailable)"
  echo "kernel=$(uname -r 2>/dev/null || echo unavailable)"
  if command -v getconf >/dev/null 2>&1; then
    echo "device_glibc=$(getconf GNU_LIBC_VERSION 2>/dev/null || echo unavailable)"
  fi
  if [ -z "$LIB" ]; then
    echo 'webkit_lib_status=not_found'
    echo 'result=NO_WPE_LIBRARY'
  else
    record_elf "$LIB" webkit_lib
    ROOT=${LIB%/lib/libWPEWebKit-2.0.so.1}
    for name in WPEWebProcess WPENetworkProcess WPEGPUProcess; do
      record_elf "$ROOT/libexec/wpe-webkit-2.0/$name" "$name"
    done
    if [ "$MODE" = --hash ]; then
      if command -v sha256sum >/dev/null 2>&1; then
        echo 'sha256_whole_library_begin'
        sha256sum "$LIB" 2>&1 || true
        echo 'sha256_whole_library_end'
      else
        echo 'sha256_whole_library=sha256sum_unavailable'
      fi
    else
      echo 'sha256_whole_library=skipped_quick_mode'
    fi
  fi
  echo 'webkit_executed=no'
  echo 'done=yes'
} > "$REPORT" 2>&1
code=$?
if [ "$code" -ne 0 ]; then echo "ERROR: could not write $REPORT" >&2; exit "$code"; fi
cat "$REPORT"
echo "REPORT=$REPORT"
exit 0
