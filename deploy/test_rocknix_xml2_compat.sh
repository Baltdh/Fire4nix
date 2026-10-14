#!/usr/bin/env bash
# Regression for R36H: the distro stores the old xml2 SONAME in /usr/lib/compat.
# The WPE-only loader must be able to use it without modifying /usr/lib.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/runtime/lib" "$TMP/compat"
cp /bin/true "$TMP/runtime/lib/libWPEWebKit-2.0.so.1"
cp /bin/true "$TMP/compat/libxml2.so.2"
printf '\267\000' | dd of="$TMP/compat/libxml2.so.2" bs=1 seek=18 conv=notrunc 2>/dev/null
cat > "$TMP/bin/readelf" <<'READELF'
#!/bin/sh
[ "${1:-}" = -d ] || exit 2
case "${2:-}" in
 *libWPEWebKit-2.0.so.1)
  [ "${TEST_WPE_NO_XML2:-0}" = 1 ] ||
    echo ' 0x01 (NEEDED) Shared library: [libxml2.so.2]'
  ;;
 *libxml2.so.2)
  [ "${TEST_COMPAT_BAD_SONAME:-0}" = 1 ] ||
    echo ' 0x0e (SONAME) Library soname: [libxml2.so.2]'
  ;;
 *) exit 1 ;;
esac
READELF
chmod +x "$TMP/bin/readelf"

check() {
  env PATH="$TMP/bin:$PATH" \
      FIRE4NIX_WPE_COMPAT_LIBXML2="$TMP/compat/libxml2.so.2" \
      LD_LIBRARY_PATH="$TMP/original" "$@" \
      bash -c '
        APP_DIR="$1"
        source "$2"
        fire4nix_wpe_enable_rocknix_xml2_compat "$3" "$4"
        printf "LOADER=%s\n" "$LD_LIBRARY_PATH"
      ' bash "$TMP" "$ROOT/navegador-definitivo/scripts/fire4nix_env.sh" \
      "$TMP/runtime/lib/libWPEWebKit-2.0.so.1" "$TMP/runtime/lib"
}
check > "$TMP/valid.log" 2>&1
grep -Fx "LOADER=$TMP/original:$TMP/compat" "$TMP/valid.log"
grep -q 'using ROCKNIX libxml2.so.2 compatibility provider' "$TMP/valid.log"
TEST_COMPAT_BAD_SONAME=1 check > "$TMP/bad-soname.log" 2>&1
grep -Fx "LOADER=$TMP/original" "$TMP/bad-soname.log"
TEST_WPE_NO_XML2=1 check > "$TMP/no-need.log" 2>&1
grep -Fx "LOADER=$TMP/original" "$TMP/no-need.log"
printf '\076\000' | dd of="$TMP/compat/libxml2.so.2" bs=1 seek=18 conv=notrunc 2>/dev/null
check > "$TMP/wrong-arch.log" 2>&1
grep -Fx "LOADER=$TMP/original" "$TMP/wrong-arch.log"
echo 'PASS: WPE-only ROCKNIX xml2 compat provider selected safely; incompatible versions not activated'
