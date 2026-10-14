#!/usr/bin/env python3
"""Stage a WPE *core-only* ROCKNIX Tools candidate from verified ARM64 CI files.

Includes the WPEWebKit shared library and its three helper processes, but NOT
the shared-library dependency closure. Never present this as a complete or
sandbox-validated ROCKNIX browser. Build-side Python only; the handheld does
not need Python to launch or verify the staged bundle.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import zipfile

PROCESSES = ("WPEWebProcess", "WPENetworkProcess", "WPEGPUProcess")
ARCHIVE_ROOT = "Fire4Nix-ROCKNIX-Tools-WPE-CORE-EXPERIMENTAL"
ARCHIVE_NAME = "Fire4Nix-ROCKNIX-ARM64-WPE-CORE-EXPERIMENTAL.zip"


def check_elf(path, machine):
    if not path.is_file():
        raise ValueError(f"required WPE component missing: {path}")
    if path.is_symlink():
        raise ValueError(f"source must be a resolved regular ELF: {path}")
    with path.open("rb") as stream:
        header = stream.read(20)
    if len(header) < 20 or header[:6] != b"\x7fELF\x02\x01":
        raise ValueError(f"not ELF64 little-endian: {path}")
    if int.from_bytes(header[18:20], "little") != machine:
        raise ValueError(f"wrong ELF machine for {path}; expected {machine}")


def file_sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def manifest(root, output):
    rows = []
    for path in sorted(root.rglob("*")):
        if not path.is_file() or path == output:
            continue
        if path.is_symlink():
            raise ValueError(f"refusing symlink in portable WPE bundle: {path}")
        rel = path.relative_to(root).as_posix()
        if "\n" in rel or "\\" in rel or rel.startswith("/") or ".." in Path(rel).parts:
            raise ValueError(f"unsafe manifest entry: {rel}")
        rows.append(f"{file_sha256(path)}  {rel}\n")
    if not rows:
        raise ValueError("empty WPE manifest")
    output.write_text("".join(rows), encoding="utf-8")


def stage(source_candidate, webkit, process_dir, output_dir, machine, closure_report=None):
    source = source_candidate.resolve(strict=True)
    if not (source / "Fire4Nix" / "Fire4Nix.sh").is_file():
        raise ValueError("expected launcher-only Tools staging tree containing Fire4Nix.sh")
    if not (source / "Fire4Nix" / "bin" / "fire4nix-wpe-platform").is_file():
        raise ValueError("expected native WPE launcher in Tools staging tree")
    if not (source / "WPE-ABI-REQUIREMENTS.json").is_file():
        raise ValueError("ABI manifest missing from launcher-only candidate")

    abi = json.loads((source / "WPE-ABI-REQUIREMENTS.json").read_text())
    if abi.get("schema") != "fire4nix-wpe-abi-v1" or abi.get("expected_elf_machine") != machine:
        raise ValueError("build-origin WPE ABI manifest does not match target architecture")
    required_roles = {"launcher", "WPEWebKit", *PROCESSES}
    if not required_roles.issubset(abi.get("components", {})):
        raise ValueError("WPE ABI manifest lacks one or more required ELF roles")

    paths = {"launcher": source / "Fire4Nix" / "bin" / "fire4nix-wpe-platform",
             "WPEWebKit": webkit.resolve(strict=True)}
    paths.update({proc: (process_dir / proc).resolve(strict=True) for proc in PROCESSES})
    for role, path in paths.items():
        check_elf(path, machine)
        if file_sha256(path) != abi["components"][role]["sha256"]:
            raise ValueError(f"WPE ELF component does not match ABI manifest: {role}")

    output_dir.mkdir(parents=True, exist_ok=True)
    target = output_dir / ARCHIVE_ROOT
    if target.exists():
        shutil.rmtree(target)
    shutil.copytree(source, target, symlinks=False)
    runtime = target / "Fire4Nix" / "runtime" / "aarch64"
    lib = runtime / "lib"
    exec_dir = runtime / "libexec" / "wpe-webkit-2.0"
    lib.mkdir(parents=True)
    exec_dir.mkdir(parents=True)
    shutil.copy2(paths["WPEWebKit"], lib / "libWPEWebKit-2.0.so")
    for process in PROCESSES:
        dest = exec_dir / process
        shutil.copy2(paths[process], dest)
        dest.chmod(dest.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    manifest(runtime, runtime / "SHA256SUMS")

    # Needed-by records are obtained from the exact matching five ELF files.
    # This inventory deliberately does not claim to resolve transitive
    # dependencies or dynamically loaded graphics/multimedia plugins.
    provided = {"libWPEWebKit-2.0.so"}
    direct_needed_by = {
        role: sorted(set(abi["components"][role].get("needed", [])))
        for role in ("launcher", "WPEWebKit", *PROCESSES)
    }
    external = sorted(set(dep for values in direct_needed_by.values()
                          for dep in values if dep not in provided))
    # ROCKNIX-side diagnostics should not need Python or a JSON parser.
    # Each entry is a literal ELF DT_NEEDED soname from this Debian build,
    # never a pathname, command or source of installation instructions.
    import re
    if any(not re.fullmatch(r"[A-Za-z0-9_.+-]+", name) for name in external):
        raise ValueError("unsafe system dependency SONAME in WPE ABI inventory")
    (target / "WPE-CORE-NEEDED.txt").write_text(
        "".join(name + "\n" for name in external), encoding="utf-8"
    )
    (target / "WPE-CORE-SYSTEM-DEPENDENCIES.json").write_text(
        json.dumps({
            "schema": "fire4nix-wpe-core-needed-v1",
            "qualification": "direct ELF NEEDED only; ROCKNIX device ABI, transitive and dlopen dependencies NOT verified",
            "bundled_sonames": sorted(provided),
            "direct_needed_by": direct_needed_by,
            "system_or_additional_bundle_dependencies": external,
        }, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    if closure_report is not None:
        # Closure metadata is generated from the same five trusted ARM64 CI
        # binaries. Keep all system dependencies external to this candidate.
        closure = json.loads(closure_report.read_text())
        if closure.get("schema") != "fire4nix-wpe-dependency-closure-v1" or closure.get("expected_elf_machine") != machine:
            raise ValueError("dependency closure schema or architecture mismatch")
        if set(closure.get("components", {})) != set(paths):
            raise ValueError("dependency closure missing/adding ELF roles")
        all_needed = closure.get("all_system_sonames", [])
        transitive = closure.get("transitive_only_sonames", [])
        if (not isinstance(all_needed, list) or not isinstance(transitive, list) or
                len(all_needed) != len(set(all_needed)) or len(transitive) != len(set(transitive)) or
                any(not isinstance(name, str) or not re.fullmatch(r"[A-Za-z0-9_.+-]+", name)
                    for name in all_needed + transitive)):
            raise ValueError("invalid or duplicate SONAME in dependency closure")
        if (set(external) - set(all_needed) or set(transitive) - set(all_needed) or
                "libWPEWebKit-2.0.so" in all_needed or
                not isinstance(closure.get("qualification"), str) or
                "UNVERIFIED" not in closure["qualification"]):
            raise ValueError("dependency closure incomplete or incorrectly qualified")
        (target / "WPE-CORE-DEPENDENCY-CLOSURE.json").write_text(
            json.dumps(closure, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        (target / "WPE-CORE-ALL-NEEDED.txt").write_text(
            "".join(name + "\n" for name in sorted(all_needed)), encoding="utf-8"
        )
        (target / "WPE-CORE-TRANSITIVE-NEEDED.txt").write_text(
            "".join(name + "\n" for name in sorted(transitive)), encoding="utf-8"
        )

    (target / "LEIA-ANTES-DE-TESTAR.txt").write_text(
        "Fire4Nix WPE CORE — EXPERIMENTAL PARA ROCKNIX/R36H\n\n"
        "Inclui launcher ARM64, libWPEWebKit-2.0.so e 3 processos WebKit.\n"
        "NAO E UM NAVEGADOR COMPLETO OU VALIDADO NO R36H.\n"
        "Dependencias transitivas, plugins, graficos, sandbox e ABI do ROCKNIX\n"
        "NAO foram empacotados ou validados. Bibliotecas compartilhadas de\n"
        "sistema precisam existir no ROCKNIX e ser compativeis.\n"
        "Os hashes do runtime sao verificados ANTES de ativar LD_LIBRARY_PATH.\n"
        "WPE-CORE-SYSTEM-DEPENDENCIES.json lista bibliotecas diretamente\n"
        "WPE-CORE-NEEDED.txt inclui a lista direta para diagnostico sem Python.\n"
        "WPE-CORE-ALL-NEEDED.txt (quando presente) inclui dependencias\n"
        "transitivas detectadas no Debian; nao e garantia de compatibilidade.\n"
        "necessarias da build; nao garante disponibilidade no ROCKNIX.\n"
        "GLIBC/libc, loaders do sistema e bibliotecas de drivers NAO sao copiadas.\n\n"
        "1. Extraia a pasta deste ZIP dentro de Tools.\n"
        "2. Execute Diagnostico.sh para verificar arquitetura/ABI/Wayland.\n"
        "3. Verifique /storage/fire4nix-wpe-diagnostic.log.\n"
        "4. Tente Start-Fire4Nix.sh somente depois de avaliar o diagnostico.\n"
        "NAO use sudo ou desative o sandbox. Falhas devem gerar logs.\n"
        "Aprovacao no CI Debian ARM64 NAO prova compatibilidade com ROCKNIX.\n",
        encoding="utf-8",
    )
    # Recreate the outer SHA256SUMS: inherited checksums refer to the original
    # launcher-only tree and do not cover the newly staged WPE core.
    manifest(target, target / "SHA256SUMS")

    archive = output_dir / ARCHIVE_NAME
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED, compresslevel=6, allowZip64=True) as zipf:
        for path in sorted(target.rglob("*")):
            if path.is_symlink():
                raise ValueError(f"symlink in ZIP is not supported: {path}")
            if path.is_file():
                zipf.write(path, (Path(ARCHIVE_ROOT) / path.relative_to(target)).as_posix())
    if not zipfile.ZipFile(archive).testzip() is None:
        raise ValueError("generated core ZIP is corrupt")
    (output_dir / "SHA256SUMS").write_text(
        f"{file_sha256(archive)}  {ARCHIVE_NAME}\n", encoding="utf-8"
    )
    (output_dir / "STATUS.txt").write_text(
        "EXPERIMENTAL CORE ONLY; WPE LIBRARY+3 SUBPROCESSES BUNDLED; "
        "TRANSITIVE DEPENDENCIES, SANDBOX AND ROCKNIX DEVICE UNVERIFIED\n",
        encoding="utf-8",
    )
    print(f"WPE core candidate: {archive} ({archive.stat().st_size} bytes)")
    print("Target ROCKNIX qualification: UNVERIFIED")
    return archive


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--webkit", type=Path, required=True)
    parser.add_argument("--process-dir", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--machine", type=int, default=183, help="AArch64=183, other values for fixture tests only")
    parser.add_argument("--closure", type=Path, help="trusted build-origin transitive dependency report")
    args = parser.parse_args(argv)
    try:
        stage(args.candidate, args.webkit, args.process_dir, args.out, args.machine, args.closure)
    except (OSError, ValueError, KeyError, zipfile.BadZipFile) as exc:
        print(f"WPE core staging FAILED: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
