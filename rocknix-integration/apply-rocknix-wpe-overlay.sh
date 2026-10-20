#!/bin/sh
# Install Fire4Nix-only ROCKNIX recipes into an explicit build-host SOURCE checkout.
# Never run this on R36H; it must never write to its /storage, rootfs or firmware.
set -eu
mode=${1:---check}
case "$mode" in --check|--apply) ;; *) echo 'Usage: sh apply-rocknix-wpe-overlay.sh --check|--apply' >&2; exit 2 ;; esac
self=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 2
root=${FIRE4NIX_ROCKNIX_SOURCE:-}
[ -n "$root" ] && [ -d "$root" ] || {
  echo 'ERROR: source checkout required in FIRE4NIX_ROCKNIX_SOURCE' >&2; exit 4
}
root=$(CDPATH= cd -- "$root" && pwd -P) || exit 4
case "$root" in
  /|/usr|/usr/*|/storage|/storage/*|/media/*|/mnt/*|/boot/*|/etc/*|/run/*|/var/*)
    echo 'ERROR: refusing firmware, removable-storage or system paths' >&2; exit 4 ;;
esac
FIRE4NIX_ROCKNIX_SOURCE="$root" sh "$self/audit-rocknix-rk3326-source.sh" --check >/dev/null
sh "$self/verify-rocknix-wpe-overlay.sh" >/dev/null
overlay="$self/rocknix-overlay"
for rel in security/libtasn1 network/libpsl network/glib-networking web/libsoup3; do
  target="$root/packages/$rel/package.mk"
  [ ! -e "$target" ] && [ ! -L "$target" ] || {
    echo "ERROR: would overwrite an existing ROCKNIX source recipe: $rel" >&2; exit 5
  }
done
if [ "$mode" = --check ]; then
  echo 'OVERLAY_PREFLIGHT=PASS_NO_SOURCE_FILES_CHANGED'
  echo 'SOURCE_RECIPE_WRITES=no'
  exit 0
fi
[ "${FIRE4NIX_OVERLAY_ALLOW_APPLY:-0}" = 1 ] || {
  echo 'ERROR: apply requires FIRE4NIX_OVERLAY_ALLOW_APPLY=1 on a disposable build-host checkout' >&2
  exit 5
}
for rel in security/libtasn1 network/libpsl network/glib-networking web/libsoup3; do
  target="$root/packages/$rel"
  mkdir -p "$target"
  cp "$overlay/packages/$rel/package.mk" "$target/package.mk"
  echo "OVERLAY_STAGED=$rel"
done
FIRE4NIX_ROCKNIX_SOURCE="$root" sh "$self/audit-rocknix-rk3326-source.sh" --ready
echo 'OVERLAY_APPLIED=FOUR_SOURCE_RECIPES_NOT_BUILT'
echo 'SDK_BUILT=no'
echo 'WEBKIT_COMPILED=no'
