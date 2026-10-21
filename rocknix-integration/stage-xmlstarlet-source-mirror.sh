#!/usr/bin/env bash
# Fail-closed URL-only patch for xmlstarlet in a disposable ROCKNIX 20260801 CI checkout.
set -euo pipefail
mode=${1:---check}
case "$mode" in --check|--apply) ;; *) echo 'ERROR: --check or --apply required' >&2; exit 2;; esac
root=${FIRE4NIX_ROCKNIX_SOURCE:-}
[[ -n "$root" && -d "$root" ]] || { echo 'ERROR: source checkout missing' >&2; exit 4; }
root=$(cd -- "$root" && pwd -P)
[[ ${GITHUB_ACTIONS:-} == true && -n ${GITHUB_WORKSPACE:-} ]] || { echo 'ERROR: CI only' >&2; exit 4; }
[[ "$root" == "$GITHUB_WORKSPACE/rocknix-source" ]] || { echo 'ERROR: refuse to patch checkout outside isolated workspace' >&2; exit 4; }
commit=3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb
[[ "$(git -C "$root" rev-parse HEAD)" == "$commit" ]] || { echo 'ERROR: ROCKNIX release commit mismatch' >&2; exit 4; }
recipe="$root/packages/textproc/xmlstarlet/package.mk"
[[ -f "$recipe" && ! -L "$recipe" ]] || { echo 'ERROR: xmlstarlet package.mk missing or symlink' >&2; exit 4; }
version=1.6.1
expected=15d838c4f3375332fd95554619179b69e4ec91418a3a5296e7c631b7ed19e7ca
grep -Fxq 'PKG_VERSION="1.6.1"' "$recipe" || { echo 'ERROR: unexpected xmlstarlet version' >&2; exit 5; }
grep -Fxq "PKG_SHA256=\"$expected\"" "$recipe" || { echo 'ERROR: unexpected xmlstarlet source SHA' >&2; exit 5; }
original='PKG_URL="http://netcologne.dl.sourceforge.net/project/xmlstar/${PKG_NAME}/${PKG_VERSION}/${PKG_NAME}-${PKG_VERSION}.tar.gz"'
grep -Fxq "$original" "$recipe" || { echo 'ERROR: original URL line missing/changed' >&2; exit 5; }
if [[ "$mode" == --check ]]; then
  echo 'XMLSTARLET_STAGE=READY_ONLY'
  echo 'SOURCE_MODIFIED=no'
  exit 0
fi
report=${FIRE4NIX_XMLSTARLET_REPORT:-}
[[ -n "$report" && -r "$report" ]] || { echo 'ERROR: verification report required' >&2; exit 6; }
grep -Fxq 'XMLSTARLET_SOURCE_STATUS=PASS_ORIGINAL_ROCKNIX_SHA256' "$report" || { echo 'ERROR: no verified source' >&2; exit 6; }
grep -Fxq "REQUIRED_ROCKNIX_SHA256=$expected" "$report" || { echo 'ERROR: verified SHA mismatch' >&2; exit 6; }
grep -Fxq "VERIFIED_SHA256=$expected" "$report" || { echo 'ERROR: source digest mismatch' >&2; exit 6; }
verified=$(sed -n 's/^VERIFIED_URL=//p' "$report")
case "$verified" in
  'https://sources.libreelec.tv/mirror/xmlstarlet/xmlstarlet-1.6.1.tar.gz'|
  'https://deb.debian.org/debian/pool/main/x/xmlstarlet/xmlstarlet_1.6.1.orig.tar.gz'|
  'https://downloads.sourceforge.net/project/xmlstar/xmlstarlet/1.6.1/xmlstarlet-1.6.1.tar.gz') ;;
  *) echo "ERROR: unapproved verified source: $verified" >&2; exit 6;;
esac
replacement="PKG_URL=\"$verified\""
python3 - "$recipe" "$original" "$replacement" <<'PY'
from pathlib import Path
import sys
p, old, new = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
data = p.read_text()
assert data.count(old + "\n") == 1, "xmlstarlet original URL occurrence is ambiguous"
p.write_text(data.replace(old + "\n", new + "\n", 1))
PY
grep -Fxq "$replacement" "$recipe"
grep -Fxq "PKG_SHA256=\"$expected\"" "$recipe"
echo 'XMLSTARLET_STAGE=APPLIED_VERIFIED_URL_ONLY'
echo "VERIFIED_URL=$verified"
echo 'R36H_MODIFIED=no'
