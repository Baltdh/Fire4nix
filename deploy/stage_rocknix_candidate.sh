#!/usr/bin/env bash
# Produce a portable, clearly UNVERIFIED candidate for the ROCKNIX Tools folder.
# This packages only the native launcher and the shell launchers/diagnostics.
# It DOES NOT package WebKit libraries, their subprocesses or a working sysroot.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BINARY="${1:-$ROOT/navegador-definitivo/fire4nix-wpe-platform}"
OUT="${2:-$ROOT/navegador-definitivo/dist/rocknix-candidate}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd -P)"

if [ ! -f "$BINARY" ] || [ ! -x "$BINARY" ]; then
    echo "ERROR: compiled ARM64 WPE launcher missing or not executable: $BINARY" >&2
    exit 2
fi

# Check actual executable ELF metadata, not a .sh wrapper named like an engine.
header="$(LC_ALL=C od -An -tx1 -N6 "$BINARY" | tr -d '[:space:]')"
machine="$(LC_ALL=C od -An -tx1 -j18 -N2 "$BINARY" | tr -d '[:space:]')"
if [ "$header" != 7f454c460201 ] || [ "$machine" != b700 ]; then
    echo "ERROR: expected ELF64 little-endian AArch64 launcher, got a different format" >&2
    exit 3
fi

STAGE="$OUT/Fire4Nix-ROCKNIX-Tools-CANDIDATE"
rm -rf "$STAGE"
mkdir -p "$STAGE/Fire4Nix/bin" "$STAGE/Fire4Nix/scripts"
cp "$ROOT/deploy/Fire4Nix-ROCKNIX.sh" "$STAGE/Start-Fire4Nix.sh"
cp "$ROOT/deploy/Fire4Nix-WPE-Diagnostico.sh" "$STAGE/Diagnostico.sh"
cp "$ROOT/navegador-definitivo/Fire4Nix.sh" "$STAGE/Fire4Nix/Fire4Nix.sh"
for script in fire4nix_env.sh run_browser.sh wpe_platform_launch.sh wpe_cog_launch.sh; do
    cp "$ROOT/navegador-definitivo/scripts/$script" "$STAGE/Fire4Nix/scripts/$script"
done
cp "$BINARY" "$STAGE/Fire4Nix/bin/fire4nix-wpe-platform"
chmod 755 "$STAGE/Start-Fire4Nix.sh" "$STAGE/Diagnostico.sh" \
    "$STAGE/Fire4Nix/Fire4Nix.sh" "$STAGE/Fire4Nix/bin/fire4nix-wpe-platform" \
    "$STAGE/Fire4Nix/scripts/"*.sh

cat > "$STAGE/LEIA-ANTES-DE-TESTAR.txt" <<'EOF'
Fire4Nix — CANDIDATO EXPERIMENTAL para ROCKNIX / R36H (aarch64)

ATENCAO: ESTE ARQUIVO NAO E UM NAVEGADOR COMPLETO.
O pacote inclui somente o executavel do launcher WPE e scripts de
inicializacao/diagnostico. NAO inclui libWPEWebKit, seus subprocessos nem
todas as bibliotecas necessarias. Foi compilado em Debian ARM64; o ABI do
ROCKNIX ainda NAO foi verificado. Nao existe garantia de que va abrir.

1. Extraia a pasta Fire4Nix-ROCKNIX-Tools-CANDIDATE para a pasta Tools.
2. Execute Diagnostico.sh e consulte /storage/fire4nix-wpe-diagnostic.log.
3. Se o runtime WebKit ja estiver instalado e compativel no aparelho,
   experimente Start-Fire4Nix.sh. Caso contrario, a inicializacao podera
   falhar ou tentar Cog, caso ele esteja presente.
4. Para bugs, envie os logs e o resultado do diagnostico.

Nao execute como root, nao desative o sandbox, nao substitua bibliotecas
de sistema do ROCKNIX. Aprovacao de CI != aprovacao no aparelho.
EOF

if command -v readelf >/dev/null 2>&1; then
    readelf -h "$BINARY" > "$STAGE/ELF-HEADERS.txt"
    readelf --version-info "$BINARY" > "$STAGE/ELF-SYMBOL-VERSIONS.txt"
fi

(
  cd "$STAGE"
  find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS
)

ARCHIVE="$OUT/Fire4Nix-ROCKNIX-ARM64-launcher-only-EXPERIMENTAL.zip"
python3 - "$STAGE" "$ARCHIVE" <<'PY'
import os
import pathlib
import stat
import sys
import zipfile

root = pathlib.Path(sys.argv[1])
archive = pathlib.Path(sys.argv[2])
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as zipf:
    for path in sorted(p for p in root.rglob('*') if p.is_file()):
        relative = pathlib.PurePosixPath(root.name, *path.relative_to(root).parts)
        info = zipfile.ZipInfo(str(relative))
        info.compress_type = zipfile.ZIP_DEFLATED
        mode = (stat.S_IFREG | (path.stat().st_mode & 0o777))
        info.external_attr = mode << 16
        with path.open('rb') as source:
            zipf.writestr(info, source.read())
print(f'Staged {archive} ({archive.stat().st_size} bytes)')
PY
sha256sum "$ARCHIVE" > "$OUT/SHA256SUMS"
printf '%s\n' 'STATUS: EXPERIMENTAL LAUNCHER ONLY; NO WPE LIBRARY RUNTIME BUNDLED' > "$OUT/STATUS.txt"
printf '%s\n' "Artifact: $ARCHIVE"
