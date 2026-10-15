#!/bin/sh
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 2
exec sh "$DIR/Tools/Fire4Nix/Fire4Nix-Diagnosticar.sh" --check "$@"
