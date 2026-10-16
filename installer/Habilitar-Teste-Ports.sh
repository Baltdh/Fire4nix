#!/bin/sh
# Add two stand-alone ROCKNIX Ports entries for diagnostics, without installing
# or modifying WebKit, firmware, display drivers or the normal browser shortcut.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 2
SOURCE="$HERE/Fire4Nix"
[ -s "$SOURCE/bin/fire4nix-native-aarch64" ] &&
[ -f "$HERE/Fire4Nix-Teste.sh" ] &&
[ -f "$HERE/Diagnosticar-Fire4Nix.sh" ] || {
  echo 'ERROR: extract the entire Fire4Nix test ZIP first' >&2
  exit 2
}
ROMS=${FIRE4NIX_ROMS:-}
if [ -z "$ROMS" ]; then
  for dir in /storage/games-internal/roms /storage/games-external/roms /storage/roms /roms; do
    if [ -d "$dir/ports" ] && [ -w "$dir/ports" ]; then ROMS="$dir"; break; fi
  done
fi
[ -n "$ROMS" ] && [ -d "$ROMS" ] && [ -w "$ROMS" ] || {
  echo 'ERROR: writable ROMS directory not found; use FIRE4NIX_ROMS=' >&2
  exit 2
}
mkdir -p "$ROMS/ports"
KIT="$ROMS/ports/.Fire4Nix-Teste-101"
# Use version-specific entries: do not replace the existing browser or tests.
[ ! -e "$KIT" ] || {
  echo "Test kit already present: $KIT"
  exit 0
}
for name in Fire4Nix-Teste-101.sh Fire4Nix-Grafico-101.sh; do
  if [ -e "$ROMS/ports/$name" ]; then
    echo "ERROR: existing Ports entry $name will not be overwritten" >&2
    exit 7
  fi
done
STAGE=$(mktemp -d "$ROMS/ports/.fire4nix-testkit-XXXXXXXX") || exit 7
cleanup() {
  status=$?
  trap - 0
  [ ! -d "$STAGE" ] || rm -rf "$STAGE"
  exit "$status"
}
trap cleanup 0
mkdir -p "$STAGE/Fire4Nix/bin" "$STAGE/Fire4Nix/www" "$STAGE/Fire4Nix/config"
cp "$SOURCE/bin/fire4nix-native-aarch64" "$STAGE/Fire4Nix/bin/"
cp "$SOURCE/Fire4Nix-Iniciar.sh" "$STAGE/Fire4Nix/"
cp "$SOURCE/www/inicio.html" "$STAGE/Fire4Nix/www/"
cp "$SOURCE/config/fire4nix.gptk" "$STAGE/Fire4Nix/config/"
cp "$HERE/Diagnosticar-Fire4Nix.sh" "$STAGE/"
cp "$HERE/Fire4Nix-Teste.sh" "$STAGE/"
# No copied WPE runtime: keep the test kit tiny and inspect installed copies.
chmod +x "$STAGE/Fire4Nix/bin/fire4nix-native-aarch64" || true
mv "$STAGE" "$KIT"
trap - 0
cat > "$ROMS/ports/Fire4Nix-Teste-101.sh" <<'ENTRY'
#!/bin/sh
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 2
exec sh "$HERE/.Fire4Nix-Teste-101/Fire4Nix-Teste.sh" --safe
ENTRY
cat > "$ROMS/ports/Fire4Nix-Grafico-101.sh" <<'ENTRY'
#!/bin/sh
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 2
exec sh "$HERE/.Fire4Nix-Teste-101/Fire4Nix-Teste.sh" --visual
ENTRY
chmod +x "$ROMS/ports/Fire4Nix-Teste-101.sh" "$ROMS/ports/Fire4Nix-Grafico-101.sh"
echo "TEST_KIT=$KIT"
echo 'PORTS_ENTRIES=Fire4Nix-Teste-101.sh,Fire4Nix-Grafico-101.sh'
echo 'NO_WEBKIT_COPIED=1'
echo 'Run diagnostics in Ports even if browser installation fails.'
echo 'The graphics test uses the already installed Fire4Nix if available.'
