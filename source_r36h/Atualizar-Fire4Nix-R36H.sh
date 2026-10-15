#!/bin/sh
# Fire4Nix 0.85: update an existing installation without replacing WPE binaries.
set -eu
BASE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
SOURCE="$BASE/Tools/Fire4Nix"
[ -f "$SOURCE/scripts/run_browser.sh" ] || { echo 'Pacote incompleto: scripts/run_browser.sh ausente.' >&2; exit 2; }
DEST="${FIRE4NIX_DEST:-}"
if [ -z "$DEST" ]; then
  for CANDIDATE in /storage/games-internal/roms/tools/Fire4Nix /storage/games-external/roms/tools/Fire4Nix; do
    if [ -d "$CANDIDATE" ]; then DEST=$CANDIDATE; break; fi
  done
fi
[ -n "$DEST" ] && [ -d "$DEST" ] && [ -w "$DEST" ] || { echo 'Fire4Nix existente nao encontrado. Defina FIRE4NIX_DEST.' >&2; exit 2; }
[ -s "$DEST/runtime/lib/libWPEWebKit-2.0.so.1" ] || echo 'AVISO: o runtime WPE nao existe no destino.'
STAMP=$(date +%Y%m%d-%H%M%S 2>/dev/null || echo undated)
BACKUP="$DEST/backup-prev-$STAMP-$$"
mkdir -p "$BACKUP"
for ITEM in scripts Fire4Nix.sh Fire4Nix-Diagnosticar.sh VERSION; do
  if [ -e "$DEST/$ITEM" ]; then cp -a "$DEST/$ITEM" "$BACKUP/"; fi
done
if [ -e "$SOURCE/bin/fire4nix-wpe-platform" ] || [ -d "$SOURCE/runtime" ] || [ -e "$SOURCE/fire4nix.conf" ]; then
  echo 'Pacote invalido: contem runtime, binario WPE ou configuracao do usuario.' >&2
  exit 3
fi
cp -a "$SOURCE/." "$DEST/"
chmod +x "$DEST"/Fire4Nix.sh "$DEST"/Fire4Nix-Diagnosticar.sh "$DEST"/scripts/*.sh 2>/dev/null || true
{
  echo 'Fire4Nix atualizado para 0.85-r36h-test2'
  echo "Destino: $DEST"
  echo "Backup anterior: $BACKUP"
  echo 'O executavel ARM64, bibliotecas WPE e configuracao nao foram substituidos.'
} | tee "$BACKUP/README-atualizacao.txt"
if [ -d /storage ] && [ -w /storage ]; then
  cp "$BACKUP/README-atualizacao.txt" /storage/Fire4Nix-atualizacao.txt 2>/dev/null || true
fi
