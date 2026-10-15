#!/usr/bin/env python3
"""Build lean Fire4Nix R36H update from the canonical GitHub sources.

Requires an AArch64 candidate produced by the arm64 workflow in dist-native/.
Does not bundle WebKit or modify device firmware.
"""
import hashlib
from pathlib import Path
import shutil
import stat
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "source_r36h"
DEST = ROOT / "dist"
ARCH = ROOT / "dist-native" / "fire4nix-native-086-aarch64"
ZIP_NAME = "Fire4Nix-R36H-0.87-Teste-Otimizado.zip"

RUN_FILES = (
    "Fire4Nix.sh",
    "Fire4Nix-Diagnosticar.sh",
    "Fire4Nix-R36H-Resgate.sh",
    "VERSION",
    "VERSAO-R36H.txt",
    "www/inicio.html",
)
SCRIPTS = (
    "browser_manager.sh",
    "engine_manager.sh",
    "fire4nix_env.sh",
    "project_audit.sh",
    "run_browser.sh",
    "theme_manager.sh",
    "wpe_cog_launch.sh",
    "wpe_platform_launch.sh",
)
UPDATERS = (
    "Atualizar-Fire4Nix-R36H.sh",
    "1-Verificar-Fire4Nix-R36H.sh",
    "2-Abrir-Fire4Nix-R36H.sh",
)

def copy(src, dst):
    if not src.is_file():
        raise FileNotFoundError(src)
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)

def build():
    if not ARCH.is_file():
        raise FileNotFoundError("Cross-built AArch64 binary missing: " + str(ARCH))
    data = ARCH.read_bytes()
    if data[:4] != b"\x7fELF" or data[4] != 2 or data[18:20] != b"\xb7\x00":
        raise ValueError("Candidate executable must be AArch64 ELF64")
    DEST.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory() as temp:
        stage = Path(temp)
        app = stage / "Tools" / "Fire4Nix"
        for relative in RUN_FILES:
            copy(SOURCES / "Fire4Nix" / relative, app / relative)
        for name in SCRIPTS:
            copy(SOURCES / "Fire4Nix" / "scripts" / name, app / "scripts" / name)
        for name in UPDATERS:
            copy(SOURCES / name, stage / name)
        native = stage / "Teste-Nativo-086"
        copy(ARCH, native / ARCH.name)
        copy(ROOT / "native" / "Fire4Nix-086-Teste.sh", native / "Fire4Nix-086-Teste.sh")
        (native / "SHA256SUMS.txt").write_text(
            f"{hashlib.sha256(data).hexdigest()}  {ARCH.name}\n"
        )
        open_script = '''#!/bin/sh
D=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 2
exec sh "$D/Teste-Nativo-086/Fire4Nix-086-Teste.sh" --open "$@"
'''
        smoke_script = '''#!/bin/sh
D=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 2
exec sh "$D/Teste-Nativo-086/Fire4Nix-086-Teste.sh" --smoke "$@"
'''
        (stage / "3-Testar-Navegador-086.sh").write_text(smoke_script)
        (stage / "4-Abrir-Navegador-086.sh").write_text(open_script)
        (stage / "LEIA-ME-PRIMEIRO.txt").write_text(
            "Fire4Nix 0.87 R36H / ROCKNIX — atualização leve, segura\n\n"
            "1. Extraia o ZIP, mantendo as pastas.\n"
            "2. Execute: sh Atualizar-Fire4Nix-R36H.sh\n"
            "3. Execute: sh 1-Verificar-Fire4Nix-R36H.sh\n"
            "4. Teste o novo ARM64: sh 3-Testar-Navegador-086.sh\n"
            "5. Se a página carregar, teste: sh 4-Abrir-Navegador-086.sh\n"
            "6. Diagnóstico extra: sh Teste-Nativo-086/Fire4Nix-086-Teste.sh --headless\n"
            "7. Envie /storage/Fire4Nix-086-Resultado.txt se falhar.\n\n"
            "O binário experimental é da série 0.86; atualização de scripts 0.87.\n"
            "Não contém a biblioteca WebKit (174MB). Reutiliza a instalação existente.\n"
            "NÃO substitui browser.arm64, o executável WPE antigo, nem temas, drivers,\n"
            "configuração e perfis de usuário. NÃO desativa o sandbox.\n"
            "Os logs do Terminal R36 Tools continuam independentes.\n"
        )
        # Prevent any accidental inclusion of proprietary settings, reference OS dumps,
        # ELF binaries from previous versions, or WebKit shared objects.
        expected = len(RUN_FILES) + len(SCRIPTS) + len(UPDATERS) + 6
        actual = [p for p in stage.rglob("*") if p.is_file()]
        if len(actual) != expected:
            raise RuntimeError(f"Unexpected file count {len(actual)} (expected {expected})")
        for file in actual:
            r = file.relative_to(stage).as_posix()
            if any(part in r for part in ("/runtime/", "/src/", "/emulationstation/", "/theme/", ".mozilla_profile")):
                raise ValueError("Unexpected source or settings in slim package: " + r)
            if file.name.endswith(".sh") or file.name == ARCH.name:
                file.chmod(file.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
        result = DEST / ZIP_NAME
        with zipfile.ZipFile(result, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
            for file in sorted(actual):
                z.write(file, file.relative_to(stage).as_posix())
        with zipfile.ZipFile(result) as z:
            if z.testzip():
                raise RuntimeError("ZIP integrity test failed")
            assert not any("/bin/" in n for n in z.namelist())
        digest = hashlib.sha256(result.read_bytes()).hexdigest()
        (DEST / "SHA256SUMS.txt").write_text(f"{digest}  {ZIP_NAME}\n")
        print(f"PASS: {result}, {len(actual)} files, {result.stat().st_size} bytes, SHA256={digest}")

if __name__ == "__main__":
    build()
