#!/usr/bin/env python3
"""Validate structure, portability boundaries and rejection paths for WPE core ZIP."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent
BUILDER = ROOT / "deploy" / "stage_wpe_core_candidate.py"
BASE_BUILDER = ROOT / "deploy" / "stage_rocknix_candidate.sh"
PROCESSES = ("WPEWebProcess", "WPENetworkProcess", "WPEGPUProcess")
ROLES = ("launcher", "WPEWebKit", *PROCESSES)


def run(*args, env=None):
    return subprocess.run([str(a) for a in args], capture_output=True, text=True, env=env)


def require(condition, reason):
    if not condition:
        raise AssertionError(reason)


def hash_file(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def main():
    with tempfile.TemporaryDirectory(prefix="fire4nix-core-test-") as temp:
        root = Path(temp)
        source = root / "fake-arm64"
        src = bytearray(Path("/bin/true").read_bytes())
        require(src[:6] == b"\x7fELF\x02\x01", "/bin/true not ELF64 little-endian")
        src[18:20] = (183).to_bytes(2, "little")
        source.write_bytes(src)
        source.chmod(0o755)
        proc = root / "source" / "libexec"
        proc.mkdir(parents=True)
        for name in PROCESSES:
            shutil.copy2(source, proc / name)
        library = root / "source" / "libWPEWebKit-2.0.so"
        shutil.copy2(source, library)
        abi = {
            "schema": "fire4nix-wpe-abi-v1",
            "expected_elf_machine": 183,
            "qualification": "build-origin only; target ROCKNIX unverified",
            "components": {role: {
                "sha256": hash_file(source),
                "needed": ["libWPEWebKit-2.0.so", "libc.so.6"] if role == "launcher" else ["libc.so.6"],
            } for role in ROLES},
        }
        abi_path = root / "abi.json"
        abi_path.write_text(json.dumps(abi))
        stage_dir = root / "base"
        import os
        environment = dict(os.environ, FIRE4NIX_WPE_ABI_MANIFEST=str(abi_path))
        baseline = run("bash", BASE_BUILDER, source, stage_dir, env=environment)
        require(baseline.returncode == 0, "baseline candidate failed: " + baseline.stderr)
        candidate = stage_dir / "Fire4Nix-ROCKNIX-Tools-CANDIDATE"
        out = root / "core-out"
        options = ("--candidate", candidate, "--webkit", library, "--process-dir", proc,
                   "--out", out)
        success = run(sys.executable, BUILDER, *options)
        require(success.returncode == 0, "WPE core stage failed: " + success.stderr)
        archive = out / "Fire4Nix-ROCKNIX-ARM64-WPE-CORE-EXPERIMENTAL.zip"
        require(archive.is_file(), "missing experimental WPE core ZIP")
        target = out / "Fire4Nix-ROCKNIX-Tools-WPE-CORE-EXPERIMENTAL"
        inner = target / "Fire4Nix" / "runtime" / "aarch64"
        require((inner / "SHA256SUMS").is_file(), "missing portable runtime checksums")
        for part in ("lib/libWPEWebKit-2.0.so", *(f"libexec/wpe-webkit-2.0/{x}" for x in PROCESSES)):
            require((inner / part).is_file(), f"missing component {part}")
        with zipfile.ZipFile(archive) as z:
            require(z.testzip() is None, "corrupt archive")
            names = z.namelist()
            require(all(n.startswith(target.name + "/") for n in names), "escaping ZIP path")
            require(all(".." not in Path(n).parts for n in names), "ZIP path traversal")
            require(any(n.endswith("/runtime/aarch64/SHA256SUMS") for n in names),
                    "runtime manifest absent from ZIP")
            require(any(n.endswith("WPE-ABI-REQUIREMENTS.json") for n in names),
                    "ABI audit absent from ZIP")
            needed_text = z.read(target.name + "/WPE-CORE-NEEDED.txt").decode().splitlines()
            require("libc.so.6" in needed_text, "missing plain-text system dependency")
            needed = json.loads(z.read(target.name + "/WPE-CORE-SYSTEM-DEPENDENCIES.json"))
            require(needed_text == needed["system_or_additional_bundle_dependencies"], "flat dependencies do not match JSON source")
            require(needed["schema"] == "fire4nix-wpe-core-needed-v1", "needed inventory schema")
            require("libc.so.6" in needed["system_or_additional_bundle_dependencies"],
                    "unbundled libc not inventoried")
            require("libWPEWebKit-2.0.so" not in needed["system_or_additional_bundle_dependencies"],
                    "bundled WPE library incorrectly marked external")
            require("NOT verified" in needed["qualification"], "missing device qualification disclaimer")
            readme = z.read(target.name + "/LEIA-ANTES-DE-TESTAR.txt").decode()
            require("NAO E UM NAVEGADOR COMPLETO" in readme, "unqualified package")
            require("GLIBC/libc" in readme, "loader warning absent")
        check = run("bash", "-c", 'cd "$1" && sha256sum -c SHA256SUMS', "bash", inner)
        require(check.returncode == 0, "invalid runtime integrity manifest")
        check = run("bash", "-c", 'cd "$1" && sha256sum -c SHA256SUMS', "bash", target)
        require(check.returncode == 0, "invalid outer integrity manifest")
        shutil.copy2(source, proc / "WPEWebProcess")
        with (proc / "WPEWebProcess").open("ab") as f:
            f.write(b"tampering!")
        invalid = run(sys.executable, BUILDER, *options)
        require(invalid.returncode != 0 and "does not match ABI manifest" in invalid.stderr,
                "tampered subprocess accepted")
        (proc / "WPENetworkProcess").unlink()
        missing = run(sys.executable, BUILDER, *options)
        require(missing.returncode != 0, "missing helper process accepted")
        print("PASS: core bundle ZIP, ELF/ABI checks, runtime checksums, warnings, tampering and missing process")


if __name__ == "__main__":
    main()
