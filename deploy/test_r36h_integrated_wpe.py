#!/usr/bin/env python3
"""Offline integration smoke test; NEVER executes any ARM64 fixture."""
import hashlib
import importlib.util
from pathlib import Path
import shutil
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("r36h_integrated", ROOT / "stage_r36h_integrated_wpe.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def mock_arm64(path):
    data = bytearray(Path("/bin/true").read_bytes())
    data[18:20] = b"\xb7\x00"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    path.chmod(0o755)


def manifest(path, paths):
    rows = [f"{hashlib.sha256(file.read_bytes()).hexdigest()}  {file.relative_to(path).as_posix()}\n"
            for file in sorted(paths)]
    (path / "SHA256SUMS").write_text("".join(rows))


def main():
    with tempfile.TemporaryDirectory(prefix="fire4nix-r36h-integrated-") as tmp:
        base = Path(tmp)
        core = base / "core"
        addon = base / "addon"
        runtime = core / "Fire4Nix" / "runtime" / "aarch64"
        smoke = base / "Fire4Nix-WPE-Teste-Real.sh"
        binpath = core / "Fire4Nix" / "Fire4Nix.sh"
        binpath.parent.mkdir(parents=True)
        binpath.write_text("#!/bin/sh\nexit 0\n")
        mock_arm64(core / "Fire4Nix" / "bin" / "fire4nix-wpe-platform")
        core_files = [runtime / "lib" / "libWPEWebKit-2.0.so"] + [
            runtime / "libexec" / "wpe-webkit-2.0" / name
            for name in mod.HELPERS
        ]
        for f in core_files:
            mock_arm64(f)
        manifest(runtime, core_files)

        libs = []
        for i in range(62):
            p = addon / "lib" / f"libtestaddon{i:02d}.so.1"
            mock_arm64(p)
            libs.append(p)
        bwrap = addon / "bin" / "bwrap"
        mock_arm64(bwrap)
        manifest(addon, libs + [bwrap])
        smoke.write_text("#!/bin/sh\nexit 0\n")

        out = base / "output"
        archive = mod.stage(core, addon, smoke, out)
        assert archive.is_file()
        with zipfile.ZipFile(archive) as zipf:
            assert zipf.testzip() is None
            names = set(zipf.namelist())
            prefix = mod.ROOT_NAME + "/"
            expected = [
                "Start-Fire4Nix.sh", "Testar-WPE-ROCKNIX.sh",
                "Fire4Nix/runtime/aarch64/SHA256SUMS",
                "Fire4Nix/runtime/aarch64/SHA256SUMS-ADDON",
                "Fire4Nix/runtime/aarch64/bin/bwrap",
            ]
            # The staging fixture intentionally has no Start-Fire4Nix.sh.
            expected.remove("Start-Fire4Nix.sh")
            for rel in expected:
                assert prefix + rel in names, f"missing {rel}"
            assert len([name for name in names if "/lib/libtestaddon" in name]) == 62
            assert "NAO E RELEASE" in zipf.read(prefix + "LEIA-ANTES-DE-TESTAR.txt").decode()
        full_runtime = out / mod.ROOT_NAME / "Fire4Nix" / "runtime" / "aarch64"
        assert len(mod.read_checksums(full_runtime, full_runtime / "SHA256SUMS-ADDON")) == 63
        assert len(mod.read_checksums(full_runtime, full_runtime / "SHA256SUMS")) == 4
        assert "libc.so.6" not in names

        # Tampering a source add-on must fail before the staged runtime changes.
        (addon / "lib" / "libtestaddon01.so.1").write_bytes(b"corrupted")
        try:
            mod.stage(core, addon, smoke, base / "should_fail")
        except ValueError as e:
            assert "checksum mismatch" in str(e)
        else:
            raise AssertionError("tampered add-on incorrectly accepted")
        print("PASS: R36H integrated archive, 62 library add-on, bwrap, manifests, strict tamper rejection")


if __name__ == "__main__":
    main()
