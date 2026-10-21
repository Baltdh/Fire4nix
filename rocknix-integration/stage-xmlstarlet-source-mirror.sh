#!/usr/bin/env bash
# Only patch xmlstarlet source URL in a pinned, disposable ROCKNIX checkout.
set -euo pipefail
case "${1:---check}" in --check|--apply) MODE=${1:---check} ;; *)
  echo 'ERROR: use --check or --apply' >&2; exit 2 ;;
esac
root=${FIRE4NIX_ROCKNIX_SOURCE:-}
[[ -n "$root" && -d "$root" ]] || { echo 'ERROR: checkout missing' >&2; exit 4; }
root=$(cd -- "$root" && pwd -P)
[[ "${GITHUB_ACTIONS:-}" == true && -n "${GITHUB_WORKSPACE:-}" &&
   "$root" == "$GITHUB_WORKSPACE/rocknix-source" ]] || {
  echo 'ERROR: refusing non-disposable/non-CI checkout' >&2; exit 4;
}
expected_commit=3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb
[[ "$(git -C "$root" rev-parse HEAD)" == "$expected_commit" ]] || {
  echo 'ERROR: ROCKNIX 20260801 source commit differs' >&2; exit 4;
}
recipe="$root/packages/textproc/xmlstarlet/package.mk"
[[ -f "$recipe" && ! -L "$recipe" ]] || {
  echo 'ERROR: missing/unsafe xmlstarlet package.mk' >&2; exit 4;
}
sha=15d838c4f3375332fd95554619179b69e4ec91418a3a5296e7c631b7ed19e7ca
grep -Fxq 'PKG_VERSION="1.6.1"' "$recipe"
grep -Fxq "PKG_SHA256=\"$sha\"" "$recipe"
original='PKG_URL="http://netcologne.dl.sourceforge.net/project/xmlstar/${PKG_NAME}/${PKG_VERSION}/${PKG_NAME}-${PKG_VERSION}.tar.gz"'
grep -Fxq "$original" "$recipe" || { echo 'ERROR: unexpected original URL' >&2; exit 5; }
if [[ "$MODE" == --check ]]; then
  echo 'XMLSTARLET_RECIPE_PATCH=READY_ONLY'
  exit 0
fi
report=${FIRE4NIX_XMLSTARLET_REPORT:-}
[[ -f "$report" && -r "$report" ]] || { echo 'ERROR: missing verified provenance report' >&2; exit 6; }
grep -Fxq 'XMLSTARLET_SOURCE_STATUS=PASS_ORIGINAL_ROCKNIX_SHA256' "$report" || exit 6
grep -Fxq "SOURCE_REQUIRED_SHA256=$sha" "$report" || exit 6
grep -Fxq "VERIFIED_SHA256=$sha" "$report" || exit 6
verified=$(sed -n 's/^VERIFIED_URL=//p' "$report")
case "$verified" in
  'https://sources.libreelec.tv/mirror/xmlstarlet/xmlstarlet-1.6.1.tar.gz'|\
  'https://downloads.sourceforge.net/project/xmlstar/xmlstarlet/1.6.1/xmlstarlet-1.6.1.tar.gz'|\
  'https://sourceforge.net/projects/xmlstar/files/xmlstarlet/1.6.1/xmlstarlet-1.6.1.tar.gz/download') ;;
  *) echo 'ERROR: mirror not in source allowlist' >&2; exit 6 ;;
esac
python3 - "$recipe" "$original" "$verified" <<'PY'
from pathlib import Path
import sys
file, original, url = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
body = file.read_text(encoding="utf-8")
assert body.count(original + "\n") == 1, "expected one original URL line"
file.write_text(body.replace(original + "\n", f'PKG_URL="{url}"\n', 1),
                encoding="utf-8")
PY
grep -Fxq "PKG_SHA256=\"$sha\"" "$recipe"
test "$(git -C "$root" diff --name-only -- packages/textproc/xmlstarlet/package.mk)" = 'packages/textproc/xmlstarlet/package.mk'
git -C "$root" diff --check
echo 'XMLSTARLET_RECIPE_PATCH=APPLIED_VERIFIED_ORIGINAL_SHA256'
echo 'ROCKNIX_FIRMWARE_MODIFIED=no'
