#!/bin/sh
# Safe Fire4Nix upgrade: never replace the user's working browser or WPE runtime.
set -eu
BASE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 2
SOURCE="$BASE/Tools/Fire4Nix"
[ -f "$SOURCE/scripts/run_browser.sh" ] || { echo 'Pacote incompleto: falta scripts/run_browser.sh' >&2; exit 2; }
DEST="${FIRE4NIX_DEST:-}"
if [ -z "$DEST" ]; then
  for DIR in /storage/games-internal/roms/tools/Fire4Nix /storage/games-external/roms/tools/Fire4Nix /storage/roms/tools/Fire4Nix; do
    if [ -d "$DIR" ]; then DEST=$DIR; break; fi
  done
fi
[ -n "$DEST" ] && [ -d "$DEST" ] && [ -w "$DEST" ] || {
  echo 'Fire4Nix existente nao encontrado. Defina FIRE4NIX_DEST.' >&2; exit 2;
}
# Reject upgrades that attempt to include/replace executable binaries, WPE runtime or personal config.
for UNSAFE in runtime bin/fire4nix-wpe-platform bin/browser.arm64 fire4nix.conf .fire4nix .mozilla_profile; do
  [ ! -e "$SOURCE/$UNSAFE" ] || {
    echo "Pacote inseguro: contêm $UNSAFE. Atualizacao cancelada." >&2; exit 3;
  }
done
STAMP=$(date +%Y%m%d-%H%M%S 2>/dev/null || echo undated)
BACKUP="$DEST/backup-prev-$STAMP-$$"
mkdir -p "$BACKUP"
for ITEM in scripts Fire4Nix.sh Fire4Nix-R36H-Resgate.sh Fire4Nix-Diagnosticar.sh VERSION; do
  if [ -e "$DEST/$ITEM" ]; then cp -a "$DEST/$ITEM" "$BACKUP/"; fi
done
for ITEM in scripts src; do
  if [ -e "$SOURCE/$ITEM" ]; then cp -a "$SOURCE/$ITEM" "$DEST/"; fi
done
for ITEM in Fire4Nix.sh Fire4Nix-R36H-Resgate.sh Fire4Nix-Diagnosticar.sh VERSION VERSAO-R36H.txt; do
  if [ -f "$SOURCE/$ITEM" ]; then cp -a "$SOURCE/$ITEM" "$DEST/"; fi
done
if [ -d "$SOURCE/www" ] && [ ! -d "$DEST/www" ]; then cp -a "$SOURCE/www" "$DEST/"; fi
chmod +x "$DEST/Fire4Nix.sh" "$DEST"/scripts/*.sh "$DEST/Fire4Nix-R36H-Resgate.sh" "$DEST/Fire4Nix-Diagnosticar.sh" 2>/dev/null || true
{
  echo 'Atualizacao segura do Fire4Nix concluida.'
  echo "Destino: $DEST"
  echo "Backup dos launchers: $BACKUP"
  echo 'Preservados: bin/browser.arm64, bin/fire4nix-wpe-platform, runtime/, perfil, configuracoes e tema.'
  if [ ! -s "$DEST/runtime/lib/libWPEWebKit-2.0.so.1" ]; then
    echo 'ATENCAO: a biblioteca WPE portatil nao existe na instalacao.'
  fi
} | tee "$BACKUP/README-atualizacao.txt"
if [ -d /storage ] && [ -w /storage ]; then
  cp "$BACKUP/README-atualizacao.txt" /storage/Fire4Nix-atualizacao.txt 2>/dev/null || true
fi
