#!/bin/sh
# Export local, self-contained Fire4Nix after one-time installation.
# Never runs automatically (174 MB+ WebKit requires space for the archive).
set -eu
ROMS=${FIRE4NIX_ROMS:-}
if [ -z "$ROMS" ]; then
  for path in /storage/games-internal/roms /storage/games-external/roms /storage/roms /roms; do
    if [ -d "$path/ports/fire4nix-completo" ]; then ROMS=$path; break; fi
  done
fi
[ -n "$ROMS" ] || { echo "Fire4Nix is not installed under Ports" >&2; exit 2; }
SOURCE="$ROMS/ports/fire4nix-completo"
[ -s "$SOURCE/runtime/lib/libWPEWebKit-2.0.so.1" ] || { echo "Local WebKit runtime missing" >&2; exit 3; }
DEST="$ROMS/ports/Fire4Nix-R36H-BackupOffline-$(date +%Y%m%d-%H%M%S 2>/dev/null || echo undated).tar.gz"
TMP="$DEST.tmp.$$"
trap 'rm -f "$TMP" 2>/dev/null || true' EXIT HUP INT TERM
(cd "$ROMS/ports" && tar -czf "$TMP" fire4nix-completo)
[ -s "$TMP" ] || exit 4
mv "$TMP" "$DEST"
trap - EXIT HUP INT TERM
printf 'Portable backup including this device local WPE runtime: %s\n' "$DEST"
