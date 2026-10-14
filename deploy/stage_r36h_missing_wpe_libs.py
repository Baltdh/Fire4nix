#!/usr/bin/env python3
"""Stage ONLY the 62 missing SONAMEs from the 2026-10-14 R36H inventory.

Reads trusted CI build-provenance paths. Never packages libc, the system
loader, EGL, Wayland, DRM or other ROCKNIX device graphics components.
The ZIP is an experimental candidate, not a tested ROCKNIX runtime.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import zipfile

PREFIX = "Fire4Nix-R36H-WPE-Libs-EXPERIMENTAL"
SONAME = re.compile(r"^lib[A-Za-z0-9_+.-]+\.so(?:\.[A-Za-z0-9_.-]+)*$")
DENY = {"libc.so.6", "libstdc++.so.6", "libgcc_s.so.1",
        "libEGL.so.1", "libGL.so.1", "libGLESv2.so.2",
        "libgbm.so.1", "libdrm.so.2", "libwayland-client.so.0",
        "libglib-2.0.so.0", "libgio-2.0.so.0", "libgobject-2.0.so.0",
        "libWPEWebKit-2.0.so.1"}


def check_elf(path, name):
    with path.open("rb") as handle:
        head = handle.read(20)
    if len(head) < 20 or head[:6] != b"\x7fELF\x02\x01" or head[18:20] != b"\xb7\x00":
        raise ValueError(f"non ARM64 ELF provider: {name}: {path}")
    proc = subprocess.run(["readelf", "-d", str(path)], capture_output=True, text=True)
    if proc.returncode:
        raise ValueError(f"readelf failed for {name}: {proc.stderr}")
    if not re.search(r"\(SONAME\)\s+Library soname:\s*\[" + re.escape(name) + r"\]", proc.stdout):
        raise ValueError(f"ELF SONAME mismatch for {name}: {path}")


def stage(closure, wanted, out, helper, bwrap=None):
    data = json.loads(closure.read_text())
    if data.get("schema") != "fire4nix-wpe-dependency-closure-v1" or data.get("expected_elf_machine") != 183:
        raise ValueError("invalid build-origin dependency closure")
    providers = data.get("build_provider_paths", {})
    names = [line.strip() for line in wanted.read_text().splitlines() if line.strip() and not line.startswith("#")]
    if len(names) != 62 or len(names) != len(set(names)):
        raise ValueError(f"expected 62 unique R36H SONAME candidates, got {len(names)}")
    if any(not SONAME.fullmatch(name) or name in DENY or name.startswith("ld-") for name in names):
        raise ValueError("forbidden/unsafe SONAME requested")
    if not set(names) <= set(data["all_system_sonames"]):
        raise ValueError("requested library not in audited ELF closure")
    root = out / PREFIX
    libs = root / "lib"
    if root.exists():
        shutil.rmtree(root)
    libs.mkdir(parents=True)
    for name in sorted(names):
        source = Path(providers.get(name, "")).resolve()
        if not source.is_file() or not source.is_absolute():
            raise ValueError(f"missing CI provider for {name}")
        check_elf(source, name)
        shutil.copyfile(source, libs / name)
    if bwrap is not None:
        with bwrap.open("rb") as handle:
            header = handle.read(20)
        if len(header) < 20 or header[:6] != b"\\x7fELF\\x02\\x01" or header[18:20] != b"\\xb7\\x00":
            raise ValueError("Bubblewrap is not ARM64 ELF64")
        (root / "bin").mkdir()
        shutil.copyfile(bwrap, root / "bin/bwrap")
        (root / "bin/bwrap").chmod(0o755)
    install = helper.read_text()
    (root / "Instalar-Complemento-R36H.sh").write_text(install)
    (root / "Instalar-Complemento-R36H.sh").chmod(0o755)
    (root / "LEIA-ME.txt").write_text(
        "EXPERIMENTAL: 62 ARM64 library candidates absent from R36H system inventory.\n"
        "A source filename match is NOT a dynamic-linker or device sandbox validation.\n"
        "Contains third-party Debian build libraries; verify redistribution licensing\n"
        "before publication beyond local diagnostic use.\n"
        "NEVER replace ROCKNIX /usr/lib or its glibc, Wayland, Mesa/EGL, DRM drivers.\n"
        "Only apply inside the Fire4Nix runtime lib folder after checking checksum.\n"
        "Sandbox must remain enabled. Test in the real R36H after installation.\n")
    rows = []
    for file in sorted(p for p in root.rglob("*") if p.is_file()):
        relative = file.relative_to(root).as_posix()
        rows.append(f"{hashlib.sha256(file.read_bytes()).hexdigest()}  {relative}\n")
    (root / "SHA256SUMS").write_text("".join(rows))
    archive = out / (PREFIX + ".zip")
    out.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        for file in sorted(p for p in root.rglob("*") if p.is_file()):
            z.write(file, (Path(PREFIX) / file.relative_to(root)).as_posix())
    print(f"Staged {len(names)} ARM64 shared libraries: {archive} ({archive.stat().st_size} bytes)")
    print("Device compatibility, sandbox and redistribution licensing: UNVERIFIED")
    return archive


def main():
    parser = argparse.ArgumentParser()
    for arg in ("closure", "wanted", "out", "helper"):
        parser.add_argument("--" + arg, required=True, type=Path)
    parser.add_argument("--bwrap", type=Path)
    args = parser.parse_args()
    try:
        stage(args.closure, args.wanted, args.out, args.helper, args.bwrap)
    except (ValueError, OSError, json.JSONDecodeError) as exc:
        print("ADDON BUILD BLOCKED: " + str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
