#!/usr/bin/env bash
# Candidate add-on for app-local libraries. No /usr/lib writes or sandbox bypass.
set -euo pipefail
umask 077
MODE="${1:---check}"
case "$MODE" in --check|--install) ;; *) echo 'Use: bash Instalar-Complemento-R36H.sh --check|--install'; exit 2 ;; esac
HERE="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
APP="${FIRE4NIX_APP_DIR:-}"
if [ -z "$APP" ]; then
  for item in "$HERE/../Fire4Nix" "$HERE/Fire4Nix" \
      /storage/games-internal/roms/tools/Fire4Nix \
      /storage/games-external/roms/tools/Fire4Nix; do
    [ ! -f "$item/scripts/fire4nix_env.sh" ] || { APP="$item"; break; }
  done
fi
[ -n "$APP" ] || { echo 'ERROR: Fire4Nix app not found'; exit 2; }
APP="$(cd "$APP" && pwd -P)"
ROOT="$APP/runtime"
[ ! -d "$ROOT/aarch64/lib" ] || ROOT="$ROOT/aarch64"
[ -d "$ROOT/lib" ] && [ -d "$ROOT/libexec/wpe-webkit-2.0" ] || { echo 'ERROR: WPE Core missing'; exit 3; }
ROOT="$(cd "$ROOT" && pwd -P)"
[ "$(uname -m)" = aarch64 ] || {
  [ "${FIRE4NIX_ADDON_ALLOW_TEST_HOST:-0}" = 1 ] || { echo 'ERROR: requires ARM64'; exit 3; }
}
[ -d "$HERE/lib" ] && [ -f "$HERE/SHA256SUMS" ] || { echo 'ERROR: add-on incomplete'; exit 3; }
( cd "$HERE"; sha256sum -c SHA256SUMS >/dev/null ) || { echo 'ERROR: invalid add-on checksums'; exit 4; }
count=0
for src in "$HERE/lib/"*; do
  [ -f "$src" ] && [ ! -L "$src" ] || { echo "ERROR: invalid source $src"; exit 4; }
  name="$(basename "$src")"
  case "$name" in
    *[!A-Za-z0-9._+-]*|libc.so*|ld-linux*|ld-*.so*|libstdc++.so*|libWPEWebKit-2.0.so*|libGL.so*|libEGL.so*|libGLES*.so*|libgbm.so*|libdrm.so*|libwayland*.so*)
      echo "ERROR: forbidden library $name"; exit 4 ;;
  esac
  head="$(LC_ALL=C od -An -tx1 -N6 "$src" | tr -d '[:space:]')"
  machine="$(LC_ALL=C od -An -tx1 -j18 -N2 "$src" | tr -d '[:space:]')"
  [ "$head" = 7f454c460201 ] && [ "$machine" = b700 ] || { echo "ERROR: invalid ARM64 ELF $name"; exit 4; }
  dest="$ROOT/lib/$name"
  [ ! -L "$dest" ] || { echo "ERROR: symlink destination $dest"; exit 5; }
  if [ -e "$dest" ]; then
    [ -f "$dest" ] && cmp -s "$src" "$dest" || { echo "ERROR: existing different $name"; exit 5; }
  fi
  count=$((count + 1))
done
[ "$count" -eq 62 ] || { echo "ERROR: expected 62 files, got $count"; exit 5; }
echo "PASS: $count ARM64 libraries checked; no system libraries modified"
if [ "$MODE" = --check ]; then
  echo 'CHECK ONLY: no files changed. Use --install to apply inside Fire4Nix.'
  exit 0
fi
[ -w "$ROOT/lib" ] || { echo 'ERROR: app library dir is read-only'; exit 6; }
[ ! -e "$ROOT/SHA256SUMS-ADDON" ] && [ ! -L "$ROOT/SHA256SUMS-ADDON" ] || {
  echo 'ERROR: existing add-on manifest; not overwriting'; exit 6;
}
TEMP="$ROOT/.SHA256SUMS-ADDON.$$.tmp"
installed_list="$ROOT/.addon-installed.$$.list"
: > "$installed_list"
cleanup() {
  status=$?
  if [ "$status" -ne 0 ]; then
    while IFS= read -r newfile; do
      [ -z "$newfile" ] || rm -f -- "$newfile"
    done < "$installed_list"
    rm -f -- "$TEMP"
  fi
  rm -f -- "$installed_list"
}
trap cleanup EXIT
for src in "$HERE/lib/"*; do
  dest="$ROOT/lib/$(basename "$src")"
  if [ ! -e "$dest" ]; then
    cp -- "$src" "$dest"
    printf '%s\n' "$dest" >> "$installed_list"
    chmod 600 "$dest"
  fi
done
( cd "$ROOT"
  for src in "$HERE/lib/"*; do sha256sum "lib/$(basename "$src")"; done
) > "$TEMP"
( cd "$ROOT"; sha256sum -c "$(basename "$TEMP")" >/dev/null ) || {
  echo 'ERROR: failed post-install checksum verification'; exit 7;
}
chmod 600 "$TEMP"
mv "$TEMP" "$ROOT/SHA256SUMS-ADDON"
echo "INSTALLED: add-on in $ROOT/lib; core manifest remains unchanged."
echo 'WebKit sandbox remains active; run hardware WPE test next.'
