#!/bin/sh
# Install once on ROCKNIX RK3326 using the *existing local* WPE runtime.
# Does not fetch remote code, disable sandbox, or modify operating-system files.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 2
SOURCE="$HERE/Fire4Nix"
[ -f "$SOURCE/bin/fire4nix-native-aarch64" ] || { echo "No native ARM64 candidate bundled" >&2; exit 2; }
ROMS=${FIRE4NIX_ROMS:-}
if [ -z "$ROMS" ]; then
    # On dual-SD R36H devices, favor the card that already has the WPE runtime.
    for path in /storage/games-internal/roms /storage/games-external/roms /storage/roms /roms; do
        if [ -s "$path/tools/Fire4Nix/runtime/lib/libWPEWebKit-2.0.so.1" ] && [ -w "$path" ]; then
            ROMS="$path"
            break
        fi
    done
    if [ -z "$ROMS" ]; then
        for path in /storage/games-internal/roms /storage/games-external/roms /storage/roms /roms; do
            if [ -d "$path/tools" ] && [ -w "$path/tools" ]; then ROMS="$path"; break; fi
        done
    fi
fi
[ -n "$ROMS" ] || { echo "ROM directory not found. Set FIRE4NIX_ROMS." >&2; exit 2; }
# An install-once command should not duplicate a 174 MB+ runtime on repeated runs.
DEST="$ROMS/ports/fire4nix-completo"
if [ -s "$DEST/bin/fire4nix-native-aarch64" ] &&
   [ -s "$DEST/runtime/lib/libWPEWebKit-2.0.so.1" ] &&
   [ -f "$DEST/Fire4Nix-Iniciar.sh" ] &&
   [ -f "$ROMS/ports/Fire4Nix.sh" ] &&
   cmp -s "$SOURCE/bin/fire4nix-native-aarch64" "$DEST/bin/fire4nix-native-aarch64" &&
   cmp -s "$SOURCE/Fire4Nix-Iniciar.sh" "$DEST/Fire4Nix-Iniciar.sh" &&
   cmp -s "$SOURCE/www/inicio.html" "$DEST/www/inicio.html" &&
   cmp -s "$SOURCE/Diagnosticar-Fire4Nix.sh" "$DEST/Diagnosticar-Fire4Nix.sh" &&
   cmp -s "$HERE/Diagnosticar-Fire4Nix.sh" "$DEST/Diagnosticar-Fire4Nix.sh"; then
    if sh "$DEST/Fire4Nix-Iniciar.sh" --check-platform >/dev/null 2>&1; then
        echo "Fire4Nix already installed and API-compatible: $DEST"
        exit 0
    fi
fi
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
mkdir -p "$ROMS/ports"
# On Linux filesystems hardlinks can reuse the read-only WebKit runtime safely.
# FAT/exFAT and separate SD cards cannot hardlink: keep the complete copy fallback.
HARDLINK_RUNTIME=0
LINK_TEST="$ROMS/ports/.fire4nix-hardlink-test-$"
if ln "$SRC_RUNTIME/lib/libWPEWebKit-2.0.so.1" "$LINK_TEST" 2>/dev/null; then
    HARDLINK_RUNTIME=1
    rm -f "$LINK_TEST"
fi
# Check free space according to the actual copy method.
if [ "$HARDLINK_RUNTIME" -eq 1 ]; then
    required_kb=0
else
    required_kb=$(du -sk "$SRC_RUNTIME" 2>/dev/null | awk '{print $1}')
fi
available_kb=$(df -Pk "$ROMS/ports" 2>/dev/null | awk 'NR==2 {print $4}')
case "$required_kb:$available_kb" in
  *[!0-9:]*|:*|*:) ;;
  *) if [ "$available_kb" -lt "$((required_kb + 32768))" ]; then
      echo "Insufficient free space to safely copy the private WPE runtime." >&2
      echo "Required approximately $((required_kb / 1024 + 32)) MiB; available $((available_kb / 1024)) MiB." >&2
      exit 6
     fi ;;
esac
# Each invocation stages a new copy and keeps the previously working install
# available for rollback until both directory and Ports entry are activated.
umask 077
STAGE="$ROMS/ports/.fire4nix-staging-$$"
PORT_TEMP="$ROMS/ports/.Fire4Nix.sh.$$.tmp"
BACKUP=""
OLD_MOVED=0
NEW_MOVED=0
COMMITTED=0
cleanup() {
    status=$?
    trap - 0 HUP INT TERM
    if [ "$COMMITTED" -ne 1 ]; then
        if [ "$NEW_MOVED" -eq 1 ] && [ -d "$DEST" ]; then
            # The fresh install is disposable; preserve it for investigation.
            mv "$DEST" "$DEST.failed-$$" 2>/dev/null || true
        fi
        if [ "$OLD_MOVED" -eq 1 ] && [ -d "$BACKUP" ]; then
            mv "$BACKUP" "$DEST" 2>/dev/null || true
        fi
    fi
    [ ! -e "$PORT_TEMP" ] || rm -f "$PORT_TEMP"
    [ ! -d "$STAGE" ] || rm -rf "$STAGE"
    exit "$status"
}
trap cleanup 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
if [ -e "$STAGE" ] || [ -e "$PORT_TEMP" ]; then
    echo "Temporary installation paths already occupied; aborting safely." >&2
    exit 7
fi
mkdir -p "$STAGE"
cp -a "$SOURCE/." "$STAGE/"
if [ ! -s "$STAGE/runtime/lib/libWPEWebKit-2.0.so.1" ]; then
    mkdir -p "$STAGE/runtime"
    if [ "$HARDLINK_RUNTIME" -eq 1 ]; then
        # An immutable engine may be hardlinked across our staging/backup folders.
        # On any unsupported file, start a clean full-copy fallback.
        if ! cp -al "$SRC_RUNTIME/." "$STAGE/runtime/" 2>/dev/null; then
            rm -rf "$STAGE/runtime"
            mkdir -p "$STAGE/runtime"
            cp -a "$SRC_RUNTIME/." "$STAGE/runtime/"
        fi
    else
        cp -a "$SRC_RUNTIME/." "$STAGE/runtime/"
    fi
fi
[ -s "$STAGE/runtime/lib/libWPEWebKit-2.0.so.1" ] || exit 4
chmod +x "$STAGE"/bin/fire4nix-native-aarch64 "$STAGE"/*.sh 2>/dev/null || true
if ! sh "$STAGE/Fire4Nix-Iniciar.sh" --check-platform; then
    echo "WebKit missing dependencies or does not provide WPEPlatform." >&2
    echo "Original Fire4Nix untouched; legacy libwpe or compatible runtime required." >&2
    exit 5
fi
# Prepare the new Ports shortcut *before* moving the working directory.
cat > "$PORT_TEMP" <<'PORT'
#!/bin/sh
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 2
exec sh "$DIR/fire4nix-completo/Fire4Nix.sh" "$@"
PORT
chmod 755 "$PORT_TEMP"
if [ -e "$ROMS/ports/Fire4Nix.sh" ]; then
    SHORTCUT_BACKUP="$ROMS/ports/Fire4Nix.sh.backup-$(date +%Y%m%d-%H%M%S)-$$"
    cp -p "$ROMS/ports/Fire4Nix.sh" "$SHORTCUT_BACKUP" || exit 7
fi
if [ -e "$DEST" ]; then
    BACKUP="$DEST.backup-$(date +%Y%m%d-%H%M%S)-$$"
    mv "$DEST" "$BACKUP" || exit 7
    OLD_MOVED=1
fi
# If either move fails, cleanup() restores the old installation.
mv "$STAGE" "$DEST" || exit 7
NEW_MOVED=1
mv -f "$PORT_TEMP" "$ROMS/ports/Fire4Nix.sh" || exit 7
COMMITTED=1
echo "Installed Fire4Nix from local WPE library into $DEST"
if [ "$OLD_MOVED" -eq 1 ]; then
    echo "Prior installation preserved: $BACKUP"
fi
echo "ROCKNIX Ports shortcut activated; graphical rendering still requires real R36H testing."
