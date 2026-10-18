#!/bin/sh
# ROCKNIX Ports one-click WPE 139 diagnosis: never opens pages or modifies firmware.
set -u
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 2
if [ ! -f "$HERE/Fire4Nix-Investigar-139.sh" ]; then
  echo 'ERRO: coloque Fire4Nix-Investigar-139.sh na mesma pasta.' >&2
  exit 127
fi
exec sh "$HERE/Fire4Nix-Investigar-139.sh" --trace
