#!/bin/sh
# Install once on ROCKNIX RK3326 using the *existing local* WPE runtime.
# Does not fetch remote code, disable sandbox, or modify operating-system files.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 2
SOURCE="$HERE/Fire4Nix"
[ -f "$SOURCE/bin/fire4nix-native-aarch64" ] || { echo "No native ARM64 candidate bundled" >&2; exit 2; }
ROMS=${FIRE4NIX_ROMS:-}
if [ -z "$ROMS" ]; then
    for path in /storage/games-internal/roms /storage/games-external/roms /storage/roms /roms; do
        if [ -d "$path/tools" ] && [ -w "$path/tools" ]; then ROMS="$path"; break; fi
    done
fi
[ -n "$ROMS" ] || { echo "ROM directory not found. Set FIRE4NIX_ROMS." >&2; exit 2; }
SRC_RUNTIME=
for path in "$SOURCE/runtime" "$ROMS/tools/Fire4Nix/runtime" "$ROMS/ports/Fire4Nix/runtime" "$ROMS/ports/fire4nix-completo/runtime" /storage/games-internal/roms/tools/Fire4Nix/runtime /storage/games-external/roms/tools/Fire4Nix/runtime; do
    if [ -s "$path/lib/libWPEWebKit-2.0.so.1" ]; then SRC_RUNTIME="$path"; break; fi
done
if [ -z "$SRC_RUNTIME" ]; then
    echo "ERROR: the 174 MB WPE runtime is not in this ZIP or existing installs." >&2
    echo "Cannot install a working offline browser from launcher-only files." >&2
    exit 3
fi
for child in WPEWebProcess WPENetworkProcess WPEGPUProcess; do
    [ -s "$SRC_RUNTIME/libexec/wpe-webkit-2.0/$child" ] || {
        echo "Missing WPE subprocess: $child" >&2; exit 3;
    }
done
DEST="$ROMS/ports/fire4nix-completo"
mkdir -p "$ROMS/ports"
STAGE="$ROMS/ports/.fire4nix-staging-$$"
trap 'rm -rf "$STAGE" 2>/dev/null || true' EXIT HUP INT TERM
mkdir -p "$STAGE"
cp -a "$SOURCE/." "$STAGE/"
if [ ! -s "$STAGE/runtime/lib/libWPEWebKit-2.0.so.1" ]; then
    mkdir -p "$STAGE/runtime"
    cp -a "$SRC_RUNTIME/." "$STAGE/runtime/"
fi
[ -s "$STAGE/runtime/lib/libWPEWebKit-2.0.so.1" ] || exit 4
chmod +x "$STAGE"/bin/fire4nix-native-aarch64 "$STAGE"/*.sh 2>/dev/null || true
if ! sh "$STAGE/Fire4Nix-Iniciar.sh" --check-library; then
    echo "WebKit is missing loader dependencies. Original installation left intact." >&2
    exit 5
fi
if [ -e "$DEST" ]; then
    BACKUP="$DEST.backup-$(date +%Y%m%d-%H%M%S)-$$"
    mv "$DEST" "$BACKUP"
    echo "Old installation preserved: $BACKUP"
fi
mv "$STAGE" "$DEST"
trap - EXIT HUP INT TERM
cat > "$ROMS/ports/Fire4Nix.sh" <<'PORT'
#!/bin/sh
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 2
exec sh "$DIR/fire4nix-completo/Fire4Nix.sh" "$@"
PORT
chmod +x "$ROMS/ports/Fire4Nix.sh"
echo "Installed Fire4Nix from local WPE library into $DEST"
echo "Next: launch Fire4Nix from the ROCKNIX Ports menu; rendering remains unverified."
