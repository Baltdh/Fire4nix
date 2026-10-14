#!/usr/bin/env python3
"""Build ONE experimental R36H Tools archive from verified matching CI trees.

Only app-local dependencies are copied. Device libc, EGL/Wayland/Mali,
DRM and other system graphics remain untouched. This does not establish
device compatibility or WebKit sandbox correctness.
"""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import sys
import zipfile

ROOT_NAME = "Fire4Nix-R36H-TOOLS-INTEGRATED-EXPERIMENTAL"
ARCHIVE_NAME = ROOT_NAME + ".zip"
HELPERS = ("WPEWebProcess", "WPENetworkProcess", "WPEGPUProcess")
SONAME = re.compile(r"lib[A-Za-z0-9_.+-]+\.so(?:\.[A-Za-z0-9_.-]+)*\Z")
FORBIDDEN = re.compile(
    r"^(?:libc\.so|ld-linux|ld-|libstdc\+\+\.so|libWPEWebKit-2\.0\.so|"
    r"libGL\.so|libEGL\.so|libGLES|libgbm\.so|libdrm\.so|"
    r"libwayland|libmali)", re.IGNORECASE
)


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def checked_files(root):
    root = root.resolve(strict=True)
    for file in root.rglob("*"):
        if file.is_symlink():
            raise ValueError(f"symlink forbidden in staged tree: {file}")
        if file.is_file():
            yield file


def read_checksums(root, manifest):
    if not manifest.is_file() or manifest.is_symlink():
        raise ValueError(f"checksum manifest missing or invalid: {manifest}")
    entries = {}
    for line in manifest.read_text(encoding="utf-8").splitlines():
        if len(line) < 67 or line[64:66] != "  ":
            raise ValueError(f"invalid checksum entry in {manifest}")
        checksum, filename = line[:64], line[66:]
        path = PurePosixPath(filename)
        if not re.fullmatch(r"[0-9a-f]{64}", checksum) or (
            path.is_absolute() or ".." in path.parts or "." in path.parts
            or "\\" in filename or filename in entries
        ):
            raise ValueError(f"unsafe checksum entry: {filename}")
        candidate = root.joinpath(*path.parts)
        if not candidate.is_file() or candidate.is_symlink():
            raise ValueError(f"missing checksum target: {filename}")
        if digest(candidate) != checksum:
            raise ValueError(f"checksum mismatch: {filename}")
        entries[filename] = checksum
    if not entries:
        raise ValueError(f"empty checksum manifest: {manifest}")
    return entries


def write_checksums(root, filename="SHA256SUMS"):
    manifest = root / filename
    rows = []
    for file in sorted(checked_files(root)):
        if file == manifest:
            continue
        rel = file.relative_to(root).as_posix()
        if "\n" in rel or "\\" in rel:
            raise ValueError(f"unsafe filename: {rel}")
        rows.append(f"{digest(file)}  {rel}\n")
    manifest.write_text("".join(rows), encoding="utf-8")


def elf_arm64(path):
    with path.open("rb") as src:
        data = src.read(20)
    return len(data) == 20 and data[:6] == b"\x7fELF\x02\x01" and data[18:20] == b"\xb7\x00"


def stage(core, addon, smoke, dest):
    core = core.resolve(strict=True)
    addon = addon.resolve(strict=True)
    smoke = smoke.resolve(strict=True)
    dest.mkdir(parents=True, exist_ok=True)
    dest = dest.resolve(strict=True)

    if not (core / "Fire4Nix" / "Fire4Nix.sh").is_file():
        raise ValueError("expected WPE Core staging tree, with Fire4Nix/Fire4Nix.sh")
    runtime = core / "Fire4Nix" / "runtime" / "aarch64"
    original_core_checksums = read_checksums(runtime, runtime / "SHA256SUMS")
    for relative in ("lib/libWPEWebKit-2.0.so", *(
        "libexec/wpe-webkit-2.0/" + name for name in HELPERS
    )):
        if relative not in original_core_checksums or not elf_arm64(runtime / relative):
            raise ValueError(f"incomplete or non-ARM64 WebKit core: {relative}")

    read_checksums(addon, addon / "SHA256SUMS")
    libs = sorted((addon / "lib").iterdir())
    if len(libs) != 62 or any(
        not file.is_file() or file.is_symlink() or
        not SONAME.fullmatch(file.name) or FORBIDDEN.match(file.name) or
        not elf_arm64(file)
        for file in libs
    ):
        raise ValueError("add-on must contain 62 safe regular ARM64 library files")
    bin_bwrap = addon / "bin" / "bwrap"
    if not bin_bwrap.is_file() or bin_bwrap.is_symlink() or not elf_arm64(bin_bwrap):
        raise ValueError("verified AArch64 Bubblewrap helper is required")
    if not smoke.is_file() or smoke.is_symlink():
        raise ValueError("hardware WPE smoke test missing")

    target = dest / ROOT_NAME
    if target.exists():
        shutil.rmtree(target)
    shutil.copytree(core, target, symlinks=False)
    target_runtime = target / "Fire4Nix" / "runtime" / "aarch64"
    additive = []
    for src in libs:
        rel = "lib/" + src.name
        dst = target_runtime / rel
        if dst.exists() or dst.is_symlink():
            raise ValueError(f"add-on would overwrite core library: {rel}")
        shutil.copy2(src, dst)
        additive.append(rel)
    (target_runtime / "bin").mkdir(exist_ok=True)
    dst = target_runtime / "bin" / "bwrap"
    if dst.exists() or dst.is_symlink():
        raise ValueError("add-on would overwrite Bubblewrap")
    shutil.copy2(bin_bwrap, dst)
    dst.chmod(dst.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    additive.append("bin/bwrap")
    (target_runtime / "SHA256SUMS-ADDON").write_text(
        "".join(f"{digest(target_runtime / rel)}  {rel}\n" for rel in sorted(additive)),
        encoding="utf-8"
    )
    read_checksums(target_runtime, target_runtime / "SHA256SUMS")
    read_checksums(target_runtime, target_runtime / "SHA256SUMS-ADDON")

    test_dst = target / "Testar-WPE-ROCKNIX.sh"
    shutil.copy2(smoke, test_dst)
    test_dst.chmod(test_dst.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    (target / "LEIA-ANTES-DE-TESTAR.txt").write_text(
        "Fire4Nix R36H: PACOTE INTEGRADO EXPERIMENTAL (NAO E RELEASE)\n"
        "WPE core + 62 bibliotecas adicionais + bwrap, todos dentro do app.\n"
        "NAO substitui libc, loader, Wayland, EGL, Mesa nem driver Mali do ROCKNIX.\n"
        "O sandbox fica ativo. Nao use sudo ou variaveis de desativacao do sandbox.\n"
        "INCOMPATIBILIDADE POSSVEL: bibliotecas transitorias, GIO, TLS e drivers.\n"
        "NAO foi comprovada abertura no R36H fisico; os testes GitHub nao bastam.\n\n"
        "1. Extraia esta pasta dentro de /storage/games-internal/roms/tools/.\n"
        "2. Evite misturar com pastas antigas, nem instalar em Tools/Tools.\n"
        "3. Rode Diagnostico.sh. Consulte /storage/fire4nix-wpe-diagnostic.log.\n"
        "4. Rode Testar-WPE-ROCKNIX.sh --headless, depois --wayland.\n"
        "5. Somente se o teste tiver sucesso, rode Start-Fire4Nix.sh.\n"
        "6. Envie os relatorios em /storage/fire4nix-device-tests/ se falhar.\n"
        "Artefato de diagnostico; a distribuicao exige auditoria de licencas.\n",
        encoding="utf-8"
    )
    write_checksums(target)
    read_checksums(target, target / "SHA256SUMS")
    archive = dest / ARCHIVE_NAME
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED, compresslevel=6, allowZip64=True) as zipf:
        for file in sorted(checked_files(target)):
            info = zipfile.ZipInfo((Path(ROOT_NAME) / file.relative_to(target)).as_posix())
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = (stat.S_IFREG | (file.stat().st_mode & 0o777)) << 16
            with file.open("rb") as stream, zipf.open(info, "w", force_zip64=True) as out:
                shutil.copyfileobj(stream, out, length=1024 * 1024)
    with zipfile.ZipFile(archive) as handle:
        if handle.testzip() is not None:
            raise ValueError("integrated ZIP integrity check failed")
    (dest / "SHA256SUMS").write_text(f"{digest(archive)}  {ARCHIVE_NAME}\n")
    (dest / "STATUS.txt").write_text(
        "EXPERIMENTAL: WPE core + 62 add-on libs + bwrap; device runtime "
        "ABI/graphics/sandbox NOT validated. NO system library overwrite.\n")
    print(f"INTEGRATED R36H CANDIDATE: {archive} ({archive.stat().st_size} bytes)")
    print("TARGET HARDWARE AND SANDBOX: UNVERIFIED")
    return archive


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ("core", "addon", "smoke", "out"):
        p.add_argument("--" + name, required=True, type=Path)
    args = p.parse_args()
    try:
        stage(args.core, args.addon, args.smoke, args.out)
    except (ValueError, OSError, zipfile.BadZipFile) as e:
        print("INTEGRATED PACKAGE BLOCKED: " + str(e), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
