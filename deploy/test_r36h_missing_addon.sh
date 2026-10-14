#!/usr/bin/env bash
# Installation tests use 62 synthetic ARM64 ELF headers; never execute them.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
HERE="$TMP/Tools/Fire4Nix-R36H-WPE-Libs-EXPERIMENTAL"
APP="$TMP/Tools/Fire4Nix"
mkdir -p "$HERE/lib" "$APP/scripts" "$APP/runtime/lib" "$APP/runtime/libexec/wpe-webkit-2.0"
cp "$ROOT/deploy/Instalar-Complemento-WPE-R36H.sh" "$HERE/Instalar-Complemento-R36H.sh"
: > "$APP/scripts/fire4nix_env.sh"
for n in $(seq -w 1 62); do
  target="$HERE/lib/libfixture$n.so.1"
  cp /bin/true "$target"
  printf '\267\000' | dd of="$target" bs=1 seek=18 conv=notrunc 2>/dev/null
done
(cd "$HERE"; find lib -type f -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
export FIRE4NIX_APP_DIR="$APP"
export FIRE4NIX_ADDON_ALLOW_TEST_HOST=1
bash "$HERE/Instalar-Complemento-R36H.sh" --check > "$TMP/check.log" 2>&1
test ! -e "$APP/runtime/lib/libfixture01.so.1"
bash "$HERE/Instalar-Complemento-R36H.sh" --install > "$TMP/install.log" 2>&1
grep -q '^INSTALLED:' "$TMP/install.log"
test -f "$APP/runtime/SHA256SUMS-ADDON"
(cd "$APP/runtime"; sha256sum -c SHA256SUMS-ADDON >/dev/null)
bash "$HERE/Instalar-Complemento-R36H.sh" --check > "$TMP/recheck.log" 2>&1
if bash "$HERE/Instalar-Complemento-R36H.sh" --install > "$TMP/duplicate.log" 2>&1; then
  echo 'FAIL: add-on manifest silently replaced' >&2; exit 1
fi
printf 'X' >> "$APP/runtime/lib/libfixture01.so.1"
if (cd "$APP/runtime"; sha256sum -c SHA256SUMS-ADDON > "$TMP/tamper.log" 2>&1); then
  echo 'FAIL: changed library passed checksum validation' >&2; exit 1
fi
echo 'PASS: R36H add-on safe check, app-only install, signed-hash pin and tamper rejection'
