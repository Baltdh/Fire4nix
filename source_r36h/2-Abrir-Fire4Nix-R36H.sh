#!/bin/sh
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 2
ROOT=${FIRE4NIX_DEST:-}
if [ -z "$ROOT" ]; then
  for CANDIDATE in /storage/games-internal/roms/tools/Fire4Nix /storage/games-external/roms/tools/Fire4Nix; do
    if [ -d "$CANDIDATE" ]; then ROOT=$CANDIDATE; break; fi
  done
fi
if [ -n "$ROOT" ] && [ -x "$ROOT/Fire4Nix-Diagnosticar.sh" ]; then
  exec sh "$ROOT/Fire4Nix-Diagnosticar.sh" --launch --safe --root "$ROOT" "$@"
fi
echo 'Fire4Nix nao instalado neste caminho. Execute Atualizar-Fire4Nix-R36H.sh.' >&2
exit 2
