#!/bin/sh
# Fire4Nix: read-only ELF dependency selection report (no ldd, dlopen or execution).
# sh inspect-wpe-dependencies.sh [--audit|--strict] [runtime/aarch64]
set -u
MODE=${1:---audit}
case "$MODE" in --audit|--strict) ;; *) echo 'usage: inspect-wpe-dependencies.sh [--audit|--strict] [runtime-root]' >&2; exit 2;; esac
ROOT=${2:-${FIRE4NIX_WPE_ROOT:-/storage/games-external/roms/ports/Fire4Nix-RK3326-Resgate/Fire4Nix/runtime/aarch64}}
case "$ROOT" in */lib) LIB=$ROOT; ROOT=${ROOT%/lib} ;; *) LIB=$ROOT/lib;; esac
[ -d "$LIB" ] || { echo "ERROR: missing runtime/lib: $LIB" >&2; exit 2; }
command -v readelf >/dev/null 2>&1 || { echo 'ERROR: readelf missing' >&2; exit 2; }
MACHINE=${FIRE4NIX_EXPECTED_MACHINE:-AArch64}
# This search order is an investigation model, not a claim of loader precedence.
# In particular, gl4es BEFORE /usr/lib avoids ROCKNIX's character-device libGL stub.
SYSPATH=${FIRE4NIX_ABI_SYSTEM_DIRS:-/usr/lib/compat:/usr/lib/gl4es:/usr/lib:/usr/lib/mali:/lib}
REPORT=${FIRE4NIX_ABI_REPORT:-}
if [ -z "$REPORT" ]; then
  if [ -d /storage ] && [ -w /storage ]; then REPORT=/storage/Fire4Nix-Dependencias-ELF.txt
  else REPORT=${TMPDIR:-/tmp}/Fire4Nix-Dependencias-ELF-$$.txt; fi
fi
TMP=$REPORT.tmp.$$
trap 'rm -f "$TMP"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
: > "$TMP" || exit 2
missing=0; malformed=0; total=0; suspicious=0
needed_list() {
  readelf -d "$1" 2>/dev/null | awk '/\(NEEDED\)/ { gsub(/^.*Shared library: \[/,""); gsub(/\].*$/,""); print }'
}
valid_elf() {
  [ -f "$1" ] && readelf -h "$1" 2>/dev/null | grep -F 'Machine:' | grep -F "$MACHINE" >/dev/null
}
# Examine candidates in recommended order without dlopen; log unusable stubs.
resolve() {
  dep=$1
  selected=''
  IFS=:
  for searchdir in "$LIB" $SYSPATH; do
    [ -n "$searchdir" ] || continue
    candidate=$searchdir/$dep
    if [ -e "$candidate" ] || [ -L "$candidate" ]; then
      if valid_elf "$candidate"; then
        selected=$candidate
        break
      fi
      printf '  REJECT_CANDIDATE=%s\n' "$candidate" >> "$TMP"
    fi
  done
  unset IFS
  if [ -n "$selected" ]; then printf '  RESOLVED=%s -> %s\n' "$dep" "$selected" >> "$TMP"
  else
    printf '  MISSING_OR_INCOMPATIBLE=%s\n' "$dep" >> "$TMP"
    missing=$((missing+1))
  fi
}
{
  echo 'Fire4Nix WPE dependency audit v2: STATIC ONLY'
  echo "mode=$MODE"
  echo "runtime=$ROOT"
  echo "expected_machine=$MACHINE"
  echo "model_system_search_dirs=$SYSPATH"
  echo 'note=runtime_loader_may_choose_differently_due_to_RPATH_RUNPATH_LD_LIBRARY_PATH'
  echo 'note=ELF_presence_does_not_establish_symbol_or_ABI_compatibility'
} >> "$TMP"
for elf in "$LIB"/*.so "$LIB"/*.so.* "$ROOT"/libexec/wpe-webkit-2.0/*; do
  [ -f "$elf" ] || continue
  [ -L "$elf" ] && continue
  total=$((total+1))
  printf '\nELF=%s\n' "$elf" >> "$TMP"
  if ! valid_elf "$elf"; then
    printf 'INVALID_ELF_OR_MACHINE=%s\n' "$elf" >> "$TMP"
    malformed=$((malformed+1))
    continue
  fi
  readelf -d "$elf" 2>/dev/null | grep -E '\((SONAME|RPATH|RUNPATH)\)' >> "$TMP" || true
  if readelf --dyn-syms -W "$elf" 2>/dev/null | grep -E 'UND[[:space:]]+GST_CAT_DEFAULT([[:space:]]|$)' >/dev/null; then
    printf 'UNRESOLVED_REFERENCE_GST_CAT_DEFAULT=%s\n' "$elf" >> "$TMP"
    suspicious=$((suspicious+1))
  fi
  list=$(needed_list "$elf")
  if [ -z "$list" ]; then echo '  NEEDED=none' >> "$TMP"; continue; fi
  set -f
  for dep in $list; do
    printf '  NEEDED=%s\n' "$dep" >> "$TMP"
    resolve "$dep"
  done
  set +f
done
{
  echo
  echo "elf_files_scanned=$total"
  echo "invalid_elf_or_machine=$malformed"
  echo "missing_or_incompatible_needed=$missing"
  echo "libraries_with_undefined_GST_CAT_DEFAULT=$suspicious"
  if [ "$total" -eq 0 ]; then echo 'status=NO_ELF_FOUND'
  elif [ "$malformed" -ne 0 ] || [ "$missing" -ne 0 ]; then echo 'status=BLOCK_INCOMPLETE_DEPENDENCIES'
  elif [ "$suspicious" -ne 0 ]; then echo 'status=REVIEW_GST_SYMBOL_ABI'
  else echo 'status=STATIC_DEPENDENCIES_FOUND_NOT_EXECUTION_VERIFIED'; fi
  echo 'runtime_executed=no'
  echo 'firmware_modified=no'
} >> "$TMP"
mv "$TMP" "$REPORT" || exit 2
cat "$REPORT"
printf 'REPORT=%s\n' "$REPORT"
if [ "$MODE" = --strict ] && { [ "$malformed" -ne 0 ] || [ "$missing" -ne 0 ] || [ "$suspicious" -ne 0 ] || [ "$total" -eq 0 ]; }; then exit 6; fi
exit 0
