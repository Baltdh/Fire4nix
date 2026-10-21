#!/usr/bin/env bash
# Patch only the source URL of GNU configtools in a disposable ROCKNIX checkout.
# Require SHA256-verified preflight report. Do NOT run on R36H.
set -euo pipefail
mode=${1:---check}
case "$mode" in --check|--apply) ;; *) echo "Usage: --check|--apply" >&2; exit 2;; esac
root=${FIRE4NIX_ROCKNIX_SOURCE:-}
[[ -n "$root" && -d "$root" ]] || { echo "ERROR: ROCKNIX source checkout required" >&2; exit 4; }
root=$(cd -- "$root" && pwd -P)
[[ "${GITHUB_ACTIONS:-}" == true && -n "${GITHUB_WORKSPACE:-}" ]] || { echo "ERROR: only disposable CI checkout" >&2; exit 4; }
[[ "$root" == "$GITHUB_WORKSPACE/rocknix-source" ]] || { echo "ERROR: unsafe checkout path" >&2; exit 4; }
commit=3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb
[[ "$(git -C "$root" rev-parse HEAD)" == "$commit" ]] || { echo "ERROR: ROCKNIX source must be pinned 20260801" >&2; exit 4; }
recipe="$root/packages/devel/configtools/package.mk"
[[ -f "$recipe" && ! -L "$recipe" ]] || { echo "ERROR: unsafe or missing configtools recipe" >&2; exit 4; }
version=28ea239c53a2d5d8800c472bc2452eaa16e37af2
sha=6e4ebaa2a60114cf8b72d478b30e559f0c8e025d290ae3303773095104bf7bcc
grep -Fxq "PKG_VERSION=\"$version\"" "$recipe" || { echo "ERROR: unexpected source commit" >&2; exit 5; }
grep -Fxq "PKG_SHA256=\"$sha\"" "$recipe" || { echo "ERROR: SHA256 changed" >&2; exit 5; }
original='PKG_URL="http://git.savannah.gnu.org/cgit/config.git/snapshot/config-${PKG_VERSION}.tar.gz"'
replacement='PKG_URL="https://sources.libreelec.tv/mirror/configtools/configtools-${PKG_VERSION}.tar.gz"'
grep -Fxq "$original" "$recipe" || { echo "ERROR: source URL unexpectedly modified" >&2; exit 5; }
if [[ "$mode" == --check ]]; then
  echo "CONFIGTOOLS_URL_CHANGE=READY_ONLY"
  echo "SOURCE_MODIFIED=no"
  exit 0
fi
report=${FIRE4NIX_CONFIGTOOLS_REPORT:-}
[[ -n "$report" && -r "$report" ]] || { echo "ERROR: verified report missing" >&2; exit 6; }
grep -Fxq "CONFIGTOOLS_SOURCE_STATUS=PASS_ORIGINAL_ROCKNIX_SHA256" "$report" || { echo "ERROR: original SHA not verified" >&2; exit 6; }
grep -Fxq "REQUIRED_ROCKNIX_TARBALL_SHA256=$sha" "$report" || { echo "ERROR: wrong locked SHA" >&2; exit 6; }
grep -Fxq "VERIFIED_URL=https://sources.libreelec.tv/mirror/configtools/configtools-$version.tar.gz" "$report" || { echo "ERROR: wrong trusted mirror" >&2; exit 6; }
python3 - "$recipe" "$original" "$replacement" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
old, new = sys.argv[2:4]
s = p.read_text()
if s.count(old + "\n") != 1:
    raise SystemExit("ERROR: original line is not unique")
p.write_text(s.replace(old + "\n", new + "\n", 1))
PY
grep -Fxq "$replacement" "$recipe"
grep -Fxq "PKG_SHA256=\"$sha\"" "$recipe"
echo "CONFIGTOOLS_URL_CHANGE=APPLIED_VERIFIED_ORIGINAL_HASH"
echo "TOOLCHAIN_BUILT=no"
echo "R36H_MODIFIED=no"
