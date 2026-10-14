#!/usr/bin/env bash
# Structural packaging regression test. The ELF fixture is deliberately NOT
# executable on the runner after its architecture header is rewritten.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if bash "$ROOT/deploy/stage_rocknix_candidate.sh" "$ROOT/navegador-definitivo/bin/fire4nix-wpe-platform" "$TMP/bad" > "$TMP/bad.log" 2>&1; then
    echo 'FAIL: packaged a script masquerading as native ELF' >&2
    exit 1
fi
cp /bin/true "$TMP/mock-arm64"
chmod +x "$TMP/mock-arm64"
# ELF64 little-endian AArch64 machine ID 0xb7; this fixture is for archive
# validation, not for execution on the R36H or another ARM64 device.
printf '\267\000' | dd of="$TMP/mock-arm64" bs=1 seek=18 conv=notrunc 2>/dev/null
printf '%s\n' '{"schema":"fire4nix-wpe-abi-v1","qualification":"build-origin only; ROCKNIX unverified"}' > "$TMP/abi.json"
FIRE4NIX_WPE_ABI_MANIFEST="$TMP/abi.json" bash "$ROOT/deploy/stage_rocknix_candidate.sh" "$TMP/mock-arm64" "$TMP/out"
test -s "$TMP/out/Fire4Nix-ROCKNIX-ARM64-launcher-only-EXPERIMENTAL.zip"
(
  cd "$TMP/out"
  sha256sum -c SHA256SUMS
  cd Fire4Nix-ROCKNIX-Tools-CANDIDATE
  sha256sum -c SHA256SUMS
)
python3 - "$TMP/out/Fire4Nix-ROCKNIX-ARM64-launcher-only-EXPERIMENTAL.zip" <<'PY'
from pathlib import PurePosixPath
import sys
import json
import zipfile
file = sys.argv[1]
prefix = 'Fire4Nix-ROCKNIX-Tools-CANDIDATE/'
required = (
    'Start-Fire4Nix.sh',
    'Diagnostico.sh',
    'Teste-WPE-No-R36H.sh',
    'LEIA-ANTES-DE-TESTAR.txt',
    'Fire4Nix/Fire4Nix.sh',
    'Fire4Nix/scripts/fire4nix_env.sh',
    'Fire4Nix/scripts/run_browser.sh',
    'Fire4Nix/scripts/wpe_cog_launch.sh',
    'Fire4Nix/scripts/wpe_platform_launch.sh',
    'Fire4Nix/bin/fire4nix-wpe-platform',
    'SHA256SUMS',
    'WPE-ABI-REQUIREMENTS.json',
)
with zipfile.ZipFile(file) as archive:
    assert not archive.testzip(), "Corrupt ZIP"
    names = set(archive.namelist())
    for name in required:
        assert prefix + name in names, f'Missing {name}'
    for name in names:
        assert not PurePosixPath(name).is_absolute()
        assert '..' not in PurePosixPath(name).parts
    readme = archive.read(prefix + 'LEIA-ANTES-DE-TESTAR.txt').decode()
    assert 'NAO inclui libWPEWebKit' in readme
    assert 'NAO significa que elas estejam instaladas' in readme
    manifest = json.loads(archive.read(prefix + 'WPE-ABI-REQUIREMENTS.json'))
    assert manifest['schema'] == 'fire4nix-wpe-abi-v1'
    binary = archive.read(prefix + 'Fire4Nix/bin/fire4nix-wpe-platform')
    assert binary[:6] == b'\x7fELF\x02\x01' and binary[18:20] == b'\xb7\x00'
    assert archive.getinfo(prefix+'Start-Fire4Nix.sh').external_attr >> 16 & 0o111
print('PASS: safe paths, binary metadata, required Tools scripts and explicit runtime limitations')
PY
