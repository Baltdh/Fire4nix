#!/usr/bin/env python3
"""Run the actual ELF inventory against safe local build-platform fixtures."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

SCRIPT = Path(__file__).with_name("collect_wpe_abi.py")


def run(*args):
    return subprocess.run([sys.executable, str(SCRIPT), *map(str, args)],
                          capture_output=True, text=True, check=False)


def check(condition, message):
    if not condition:
        raise AssertionError(message)


def main():
    with tempfile.TemporaryDirectory(prefix="fire4nix-abi-") as tmp:
        root = Path(tmp)
        proc = root / "libexec"
        proc.mkdir()
        launcher = root / "fire4nix-wpe-platform"
        webkit = root / "libWPEWebKit-2.0.so"
        paths = [launcher, webkit] + [proc / name for name in ("WPEWebProcess", "WPENetworkProcess", "WPEGPUProcess")]
        for path in paths:
            shutil.copy2("/bin/true", path)
        machine = int.from_bytes(launcher.read_bytes()[18:20], "little")
        output = root / "manifest.json"
        base = ["--launcher", launcher, "--webkit", webkit, "--process-dir", proc,
                "--output", output, "--expect-machine", str(machine)]
        success = run(*base)
        check(success.returncode == 0, success.stderr)
        data = json.loads(output.read_text())
        check(data["schema"] == "fire4nix-wpe-abi-v1", "schema mismatch")
        check(len(data["components"]) == 5, "missing ABI inventory component")
        check(all(len(v["sha256"]) == 64 for v in data["components"].values()),
              "missing component digests")
        check("UNVERIFIED" not in data["qualification"] or "unverified" in data["qualification"].lower(),
              "qualification omitted")
        (proc / "WPEGPUProcess").unlink()
        missing = run(*base)
        check(missing.returncode == 1 and "WPEGPUProcess" in missing.stderr,
              "missing process did not fail closed")
        shutil.copy2("/bin/true", proc / "WPEGPUProcess")
        modified = bytearray(launcher.read_bytes())
        modified[18:20] = (0).to_bytes(2, "little")
        launcher.write_bytes(modified)
        wrong_machine = run(*base)
        check(wrong_machine.returncode == 1 and "e_machine" in wrong_machine.stderr,
              "mismatched ELF machine did not fail closed")
        print("PASS: ELF inventory includes launcher, WPE and all processes; missing/mismatched targets fail closed")


if __name__ == "__main__":
    main()
