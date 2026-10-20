#!/usr/bin/env bash
# Adjust only 7-zip download URL in an isolated ROCKNIX 20260801 checkout.
# Requires a verified SHA256 report. Never write to firmware or handheld SD.
set -euo pipefail
mode=${1:---check}
case "$mode" in --check|--apply) ;; *) echo 'Usage: stage-7zip-source-mirror.sh --check|--apply' >&2; exit 2;; esac
root=${FIRE4NIX_ROCKNIX_SOURCE:-}
[ -n "$root" ] && [ -d "$root" ] || { echo 'ERROR: ROCKNIX checkout required' >&2; exit 4; }
root=$(cd -- "$root" && pwd -P)
[ "${GITHUB_ACTIONS:-}" = true ] && [ -n "${GITHUB_WORKSPACE:-}" ] || {
  echo 'ERROR: stage only on a disposable GitHub Actions checkout' >&2; exit 4
}
expected_root="$GITHUB_WORKSPACE/rocknix-source"
[ "$root" = "$expected_root" ] || {
  echo "ERROR: source must be exactly $expected_root" >&2; exit 4
}
expected_commit=3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb
[ "$(git -C "$root" rev-parse HEAD)" = "$expected_commit" ] || {
  echo 'ERROR: wrong ROCKNIX 20260801 source identity' >&2; exit 4
}
recipe="$root/packages/compress/7-zip/package.mk"
[ -f "$recipe" ] && [ ! -L "$recipe" ] || { echo 'ERROR: 7-Zip recipe absent or symlinked' >&2; exit 4; }
expected_sha=bff9e69b6ca73a5b8715d7623870a39dc90ad6ce1f4d1070685843987af1af9b
grep -Fxq 'PKG_VERSION="25.00"' "$recipe" || { echo 'ERROR: unexpected 7-Zip version' >&2; exit 5; }
grep -Fxq "PKG_SHA256=\"$expected_sha\"" "$recipe" || {
  echo 'ERROR: changed upstream SHA256' >&2; exit 5
}
# This is the only line allowed to change in the disposable checkout.
original='PKG_URL="https://www.7-zip.org/a/7z${PKG_VERSION/./}-src.tar.xz"'
replacement='PKG_URL="https://downloads.sourceforge.net/project/sevenzip/7-Zip/25.00/7z2500-src.tar.xz"'
grep -Fxq "$original" "$recipe" || { echo 'ERROR: upstream PKG_URL not exactly as reviewed' >&2; exit 5; }
if [ "$mode" = --check ]; then
  echo 'MIRROR_RECIPE_PREFLIGHT=PASS_ORIGINAL_SHA_AND_URL'
  echo 'SOURCE_CHANGED=no'
  exit 0
fi
report=${FIRE4NIX_7ZIP_REPORT:-}
[ -n "$report" ] && [ -r "$report" ] || {
  echo 'ERROR: apply requires verified report from mirror probe' >&2; exit 6
}
grep -Fxq 'SOURCE_MIRROR_STATUS=PASS' "$report" || {
  echo 'ERROR: source mirror was not verified' >&2; exit 6
}
grep -Fxq "VERIFIED_SHA256=$expected_sha" "$report" || {
  echo 'ERROR: digest in report differs from ROCKNIX recipe' >&2; exit 6
}
python3 - "$recipe" "$original" "$replacement" <<'PY'
import pathlib, sys
file, old, new = sys.argv[1:]
p = pathlib.Path(file)
content = p.read_text(encoding="utf-8")
old_line = old + "\n"
if content.count(old_line) != 1:
    raise SystemExit("ERROR: original URL line changed during application")
p.write_text(content.replace(old_line, new + "\n", 1), encoding="utf-8")
PY
grep -Fxq "$replacement" "$recipe" || {
  echo 'ERROR: mirrored 7-Zip URL not applied' >&2; exit 6
}
grep -Fxq "PKG_SHA256=\"$expected_sha\"" "$recipe"
echo 'SOURCE_MIRROR_RECIPE_APPLIED=VERIFIED_SHA256_URL_ONLY'
echo 'TARGET_R36H_CHANGED=no'
echo 'TOOLCHAIN_BUILT=no'
