#!/usr/bin/env python3
"""Assemble a *first-test candidate* Ports ZIP from audited real AArch64 ELFs.

No build-host libraries, generated mocks, device firmware writes or execution
of target binaries. This is NOT proof of a successful R36H hardware test.
Inputs: exact real WPE runtime from target CI and a real ARM64 native launcher.
"""
from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import zipfile

MAX_FILES = 15000
MAX_BYTES = 1600 * 1024 * 1024
ROOT_PREFIX = "Fire4Nix"
NAMES = ("lib/libWPEWebKit-2.0.so.1",
         "libexec/wpe-webkit-2.0/WPEWebProcess",
         "libexec/wpe-webkit-2.0/WPENetworkProcess",
         "lib/wpe-webkit-2.0/injected-bundle/libWPEInjectedBundle.so")
ASSETS = ("share/wpe-webkit-2.0/inspector.gresource",
          "BUILD-REPORT.txt", "SDK-BUNDLE-REPORT.txt", "SHA256SUMS.txt")
# WebKit launches these helpers with execve; FAT/ZIP extraction cannot depend
# on executable bits surviving the GitHub artifact transport.
RUNTIME_EXECUTABLES = frozenset(("libexec/wpe-webkit-2.0/WPEWebProcess",
                                  "libexec/wpe-webkit-2.0/WPENetworkProcess"))
# GCC15 outlined atomics can survive in shared objects as undefined dynamic
# symbols. ROCKNIX RK3326 test ZIPs must not rely on unknown external LSE
# atomic helper providers even if ELF headers and SONAMEs otherwise pass.
UNDEFINED_OUTLINED_ATOMICS = re.compile(
    r"\b__aarch64_(?:cas|swp|ldadd|ldclr|ldset|ldeor)(?:p?[0-9])\w*(?:@|\b)")



def sha256_file(path: Path) -> str:
    """Hash large WPE ELF and resource payloads without buffering them in RAM."""
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def get_readelf(flag: str, file: Path) -> str:
    p = subprocess.run(["readelf", "--wide", flag, str(file)],
                       check=True, capture_output=True, text=True, timeout=40)
    return p.stdout


def elf_check(file: Path) -> None:
    header = get_readelf("-h", file)
    versions = get_readelf("-V", file)
    dynamic = get_readelf("-d", file)
    if not all(re.search(pattern, header) for pattern in (
            r"Class:\s+ELF64\b", r"Machine:\s+AArch64\b",
            r"Data:\s+2's complement, little endian")):
        raise ValueError("FOREIGN_ELF:" + file.name)
    if any((int(a), int(b)) > (2, 41) for a, b in
           re.findall(r"Name:\s*GLIBC_(\d+)\.(\d+)", versions)):
        raise ValueError("TOO_NEW_GLIBC:" + file.name)
    for value in re.findall(r"\((?:RPATH|RUNPATH)\).*?\[([^\]]*)\]", dynamic):
        if any(not (part == "$ORIGIN" or
                    (part.startswith("$ORIGIN/") and "/../" not in part))
               for part in value.split(":")):
            raise ValueError("NON_PORTABLE_RPATH:" + file.name)
    for dep in re.findall(r"\(NEEDED\).*?\[([^\]]*)\]", dynamic):
        if not dep or "/" in dep or ".." in dep or dep.startswith(("libgst", "libgstreamer")):
            raise ValueError("INVALID_OR_MEDIA_NEEDED:" + dep)
    symbols = get_readelf("--dyn-syms", file)
    if re.search(r"\bUND\s+GST_CAT_DEFAULT(?:@|\s|$)", symbols):
        raise ValueError("GST_CAT_DEFAULT_UNDEFINED")
    for row in symbols.splitlines():
        if re.search(r"\bUND\b", row):
            helper = UNDEFINED_OUTLINED_ATOMICS.search(row)
            if helper:
                raise ValueError("UNDEFINED_GCC15_OUTLINED_ATOMIC:" +
                                 file.name + ":" + helper.group(0).rstrip("@"))

    if file.name == "libWPEWebKit-2.0.so.1":
        if not re.search(r"\(SONAME\).*?\[libWPEWebKit-2\.0\.so\.1\]", dynamic):
            raise ValueError("WPE_SONAME_MISMATCH")
        if not any("webkit_web_view_get_wpe_view" in row and
                   not re.search(r"\bUND\b", row)
                   for row in symbols.splitlines()):
            raise ValueError("WPE_PLATFORM_EXPORT_MISSING")
    if file.name in ("fire4nix-native-aarch64", "WPEWebProcess", "WPENetworkProcess"):
        program = get_readelf("-l", file)
        interp = re.findall(r"\[Requesting program interpreter:\s*([^\]]+)\]", program)
        if interp != ["/lib/ld-linux-aarch64.so.1"] and interp != ["/lib64/ld-linux-aarch64.so.1"]:
            raise ValueError("INVALID_PROGRAM_LOADER:" + file.name)


def ensure_tree(root: Path) -> list[Path]:
    if not root.is_dir() or root.is_symlink():
        raise ValueError("INVALID_INPUT_DIRECTORY")
    entries = sorted(root.rglob("*"))
    if len(entries) > MAX_FILES:
        raise ValueError("TOO_MANY_INPUT_ENTRIES")
    total = 0
    regular = []
    root_abs = root.resolve(strict=True)
    for entry in entries:
        if entry.is_symlink():
            # WPE/CMake routinely installs libfoo.so -> libfoo.so.1 aliases.
            # Make an independent REGULAR ZIP entry, never archive the symlink.
            # Only a relative single-file alias wholly inside this runtime is
            # safe. Absolute, escaping, dangling and directory links are fatal.
            target = os.readlink(entry)
            if os.path.isabs(target) or ".." in PurePosixPath(target).parts:
                raise ValueError("ESCAPING_RUNTIME_SYMLINK:" + str(entry.relative_to(root)))
            try:
                resolved = entry.resolve(strict=True)
            except (OSError, RuntimeError):
                raise ValueError("BROKEN_RUNTIME_SYMLINK:" + str(entry.relative_to(root)))
            if not resolved.is_relative_to(root_abs) or not resolved.is_file():
                raise ValueError("INVALID_RUNTIME_SYMLINK_TARGET:" + str(entry.relative_to(root)))
        elif entry.is_dir():
            continue
        elif not entry.is_file():
            raise ValueError("SPECIAL_FILE_IN_PACKAGE")
        total += entry.stat().st_size
        if total > MAX_BYTES:
            raise ValueError("PACKAGE_TOO_LARGE")
        regular.append(entry)
    return regular


def require_marker(path: Path, exact: str) -> None:
    if path.is_symlink() or not path.is_file() or exact not in path.read_text().splitlines():
        raise ValueError("MISSING_VERIFIED_MARKER:" + exact)


def verify_checksums(runtime: Path) -> None:
    manifest = runtime / "SHA256SUMS.txt"
    if not manifest.is_file() or manifest.is_symlink():
        raise ValueError("MISSING_RUNTIME_HASHES")
    seen = set()
    for row in manifest.read_text().splitlines():
        match = re.fullmatch(r"([a-f0-9]{64})  (.+)", row)
        if not match:
            raise ValueError("INVALID_SHA256SUM_LINE")
        digest, relative = match.groups()
        if relative.startswith("/") or ".." in PurePosixPath(relative).parts or relative in seen:
            raise ValueError("UNSAFE_OR_DUPLICATE_HASH_PATH")
        seen.add(relative)
        file = runtime / relative
        if not file.is_file() or file.is_symlink():
            raise ValueError("MISSING_RUNTIME_HASHED_FILE:" + relative)
        if sha256_file(file) != digest:
            raise ValueError("RUNTIME_HASH_MISMATCH:" + relative)
    required = set(NAMES) | {"share/wpe-webkit-2.0/inspector.gresource"}
    if not required.issubset(seen):
        raise ValueError("UNHASHED_REQUIRED_WPE_FILE")


def source_files(installer: Path) -> list[tuple[Path, str, bool]]:
    result = []
    root_script = installer / "Fire4Nix-Direto.sh"
    if not root_script.is_file():
        raise ValueError("MISSING_PORTS_ENTRY")
    result.append((root_script, "Fire4Nix-Direto.sh", True))
    # The diagnostic Ports kit expects these three entry-point scripts beside
    # the Fire4Nix/ directory. Shipping only Fire4Nix/Fire4Nix-Teste.sh would
    # make the ZIP unable to expose Fire4Nix-Tela-101.sh after extraction.
    for name in ("Habilitar-Teste-Ports.sh", "Fire4Nix-Teste.sh",
                 "Diagnosticar-Fire4Nix.sh"):
        file = installer / name
        if not file.is_file() or file.is_symlink() or not file.stat().st_size:
            raise ValueError("MISSING_TESTKIT_INSTALLER:" + name)
        result.append((file, name, True))
    for name in ("Fire4Nix-Iniciar.sh", "Fire4Nix-Teste.sh",
                 "Diagnosticar-Fire4Nix.sh", "Fire4Nix-Inspecionar-ELF.sh"):
        file = installer / name
        if not file.is_file() or file.is_symlink():
            raise ValueError("MISSING_LAUNCHER:" + name)
        result.append((file, f"{ROOT_PREFIX}/{name}", True))
    for folder in ("www", "config"):
        d = installer / folder
        if not d.is_dir():
            raise ValueError("MISSING_LAUNCH_ASSETS:" + folder)
        for file in ensure_tree(d):
            result.append((file, f"{ROOT_PREFIX}/{folder}/{file.relative_to(d).as_posix()}", False))
    return result


def make(runtime: Path, native: Path, installer: Path, output: Path) -> dict:
    for file in NAMES + ASSETS:
        source = runtime / file
        if not source.is_file() or source.is_symlink() or not source.stat().st_size:
            raise ValueError("MISSING_REAL_WPE_COMPONENT:" + file)
    require_marker(runtime / "BUILD-REPORT.txt", "WPE_INSTALLED_ASSETS_PROFILE=strict")
    require_marker(runtime / "BUILD-REPORT.txt",
                   "WPE_INSTALLED_ASSETS_STATUS=copied_and_static_elf_checked")
    require_marker(runtime / "BUILD-REPORT.txt",
                   "GPU_PROCESS_PROFILE=disabled_verified_wayland")
    require_marker(runtime / "SDK-BUNDLE-REPORT.txt",
                   "ROCKNIX_PRIVATE_SDK_ELF_BUNDLE=PASS_STATIC_SONAMES_ONLY")
    require_marker(runtime / "SDK-BUNDLE-REPORT.txt",
                   "WPE_RUNTIME_CLOSURE=SDK_STATIC_CANDIDATES_ONLY")
    require_marker(runtime / "SDK-BUNDLE-REPORT.txt",
                   "WPE_INJECTED_BUNDLE_ELF_AUDITED=yes")
    require_marker(runtime / "SDK-BUNDLE-REPORT.txt", "R36H_INSTALLABLE=no")
    if (runtime / "libexec/wpe-webkit-2.0/WPEGPUProcess").exists():
        raise ValueError("GPU_OFF_RUNTIME_CONTAINS_GPU_PROCESS")
    files = ensure_tree(runtime)
    verify_checksums(runtime)
    if not native.is_file() or native.is_symlink() or native.name != "fire4nix-native-086-aarch64":
        raise ValueError("GENUINE_NATIVE_086_ELF_REQUIRED")
    if not installer.is_dir():
        raise ValueError("MISSING_LAUNCHER_INSTALLER")
    for path in [native] + [runtime / x for x in NAMES]:
        elf_check(path)
    for file in files:
        if file.name.endswith(".so") or ".so." in file.name:
            elf_check(file)
    added = source_files(installer)
    added.append((native, f"{ROOT_PREFIX}/bin/fire4nix-native-aarch64", True))
    added += [(f, f"{ROOT_PREFIX}/runtime/{f.relative_to(runtime).as_posix()}",
               f.relative_to(runtime).as_posix() in RUNTIME_EXECUTABLES)
              for f in files]
    names = [z[1] for z in added]
    if len(set(names)) != len(names):
        raise ValueError("DUPLICATE_ZIP_ENTRY")
    if output.exists() or output.is_symlink() or not output.parent.is_dir():
        raise ValueError("REFUSE_OUTPUT_REPLACEMENT")
    notes = (
        "Fire4Nix R36H / ROCKNIX — PRIMEIRO TESTE EXPERIMENTAL\n"
        "Este pacote foi montado com ELF AArch64 e dependencias do SDK ROCKNIX.\n"
        "Nao comprova compatibilidade de hardware, driver Mali, TLS ou Wayland.\n"
        "Nao modifica /usr nem o firmware. Primeiro teste somente HTML offline.\n"
        "Extrair a pasta Fire4Nix e Fire4Nix-Direto.sh lado a lado em roms/ports.\n"
        "Habilitar-Teste-Ports.sh cria atalhos de diagnostico sem substituir o navegador.\n"
        "Entradas: Fire4Nix-Teste-101, Fire4Nix-Grafico-101, Fire4Nix-Tela-101.\n"
        "Fire4Nix-Tela-101 abre a pagina offline interativa; confirme cores e JS OK.\n"
        "Iniciar pelo menu Ports. Enviar logs se falhar ou encerrar com 139.\n"
        "Motor WPE e binario principal sao componentes reais, nao simulacoes.\n"
        "R36H_FIRST_FRAME_VERIFIED=no\n"
        "R36H_INSTALLABLE_VERIFIED=no\n"
    )
    digest_lines = []
    try:
        with zipfile.ZipFile(output, "x", compression=zipfile.ZIP_DEFLATED,
                             compresslevel=6, allowZip64=True) as z:
            for path, dst, executable in added:
                zi = zipfile.ZipInfo(dst)
                zi.create_system = 3
                zi.external_attr = ((0o100755 if executable or dst.endswith(".sh") else 0o100644) << 16)
                zi.compress_type = zipfile.ZIP_DEFLATED
                with path.open("rb") as source, z.open(zi, "w") as target:
                    import shutil
                    shutil.copyfileobj(source, target, 1024 * 1024)
                digest_lines.append(f"{sha256_file(path)}  {dst}")
            z.writestr("LEIA-ME-PRIMEIRO.txt", notes)
            z.writestr("PACOTE-SHA256SUMS.txt", "\n".join(digest_lines) + "\n")
    except BaseException:
        output.unlink(missing_ok=True)
        raise
    return {"files": len(added), "bytes": output.stat().st_size}


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--runtime", type=Path, required=True)
    p.add_argument("--native", type=Path, required=True)
    p.add_argument("--installer", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    a = p.parse_args()
    try:
        summary = make(a.runtime, a.native, a.installer, a.output)
    except (OSError, ValueError, subprocess.CalledProcessError,
            subprocess.TimeoutExpired, UnicodeError) as err:
        print(f"FIRST_TEST_PORTS_CANDIDATE=BLOCKED:{err}", file=sys.stderr)
        return 6
    print("FIRST_TEST_PORTS_CANDIDATE=PASS_STATIC_ARM64_NOT_HARDWARE_TESTED")
    print(f"ZIP_FILES={summary['files']}")
    print(f"ZIP_BYTES={summary['bytes']}")
    print("R36H_FIRST_FRAME_VERIFIED=no")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
