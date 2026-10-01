#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SOURCE="${1:-${FIRE4NIX_WPE_RUNTIME_SOURCE:-}}"
DEST="${FIRE4NIX_WPE_RUNTIME_DEST:-$ROOT_DIR/runtime/aarch64}"

fail() {
    printf 'Fire4Nix WPE runtime staging: ERROR: %s\n' "$*" >&2
    exit 2
}

[ -n "$SOURCE" ] || fail "usage: stage_wpe_runtime.sh /path/to/prepared-wpe-runtime"
[ -d "$SOURCE" ] || fail "source runtime does not exist: $SOURCE"

if [ -d "$SOURCE/usr/libexec/wpe-webkit-2.0" ]; then
    SOURCE="$SOURCE/usr"
fi

[ -d "$SOURCE/lib" ] || fail "source must contain lib/"
[ -d "$SOURCE/libexec/wpe-webkit-2.0" ] ||
    fail "source must contain libexec/wpe-webkit-2.0/"

for process in WPEWebProcess WPENetworkProcess WPEGPUProcess; do
    [ -f "$SOURCE/libexec/wpe-webkit-2.0/$process" ] ||
        fail "source runtime is missing $process"
done

wpe_lib=""
for candidate in "$SOURCE"/lib/libWPEWebKit-2.0.so "$SOURCE"/lib/libWPEWebKit-2.0.so.*; do
    if [ -f "$candidate" ]; then
        wpe_lib="$candidate"
        break
    fi
done
[ -n "$wpe_lib" ] || fail "source runtime is missing libWPEWebKit-2.0.so"

rm -rf "$DEST"
mkdir -p "$DEST"
cp -a "$SOURCE/lib" "$DEST/lib"
mkdir -p "$DEST/libexec"
cp -a "$SOURCE/libexec/wpe-webkit-2.0" "$DEST/libexec/wpe-webkit-2.0"

if [ -d "$SOURCE/share" ]; then
    cp -a "$SOURCE/share" "$DEST/share"
fi

chmod +x "$DEST/libexec/wpe-webkit-2.0/"WPE*Process 2>/dev/null || true

MANIFEST="$DEST/runtime.manifest"
{
    printf '%s\n' "# Fire4Nix bundled WPE runtime manifest"
    printf 'source=%s\n' "$SOURCE"
    printf 'generated=%s\n' "$(date -Iseconds 2>/dev/null || date 2>/dev/null || echo unknown)"
    printf 'target=aarch64-rocknix\n'
    printf 'webkit_process_path=libexec/wpe-webkit-2.0\n'
    printf 'relocatable_patch=patches/wpewebkit/0001-fire4nix-relocatable-process-path.patch\n'
    printf '%s\n' ""
    printf '%s\n' "[sha256]"
    if command -v sha256sum >/dev/null 2>&1; then
        find "$DEST" -type f ! -name runtime.manifest -print0 2>/dev/null |
            sort -z |
            xargs -0 sha256sum |
            sed "s#  $DEST/#  #"
    fi
} > "$MANIFEST"

sh "$ROOT_DIR/scripts/verify_wpe_runtime.sh" "$DEST"
printf 'Fire4Nix WPE runtime staged at %s\n' "$DEST"
