#!/usr/bin/env python3
"""Remove verified CI-only RUNPATH from six *copies* of ROCKNIX AArch64 libs.

Original SDK artifact remains unchanged. An output overlay is a build input,
NOT a verified R36H runtime or an installable browser.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = "/home/runner/work/Fire4nix/Fire4nix"
TARGETS = {
    "libfontconfig.so": f"{ROOT}/fontconfig-target/stage/usr/lib",
    "libfontconfig.so.1": f"{ROOT}/fontconfig-target/stage/usr/lib",
    "libfontconfig.so.1.16.1": f"{ROOT}/fontconfig-target/stage/usr/lib",
    "libgcrypt.so": f"{ROOT}/gcrypt-target/stage/usr/lib",
    "libgcrypt.so.20": f"{ROOT}/gcrypt-target/stage/usr/lib",
    "libgcrypt.so.20.5.1": f"{ROOT}/gcrypt-target/stage/usr/lib",
}
DYN_META = re.compile(r"\((SONAME|NEEDED)\).*\[([^\]]+)\]")
PATH = re.compile(r"\((RPATH|RUNPATH)\).*\[([^\]]*)\]")
VERSION = re.compile(r"Name: GLIBC_(\d+)\.(\d+)")


def run(*cmd: str) -> str:
    result = subprocess.run(cmd, check=True, text=True, capture_output=True,
                            timeout=30)
    return result.stdout


def details(path: Path):
    header = run("readelf", "-h", str(path))
    if not (re.search(r"Class:\s+ELF64\b", header)
            and re.search(r"Machine:\s+AArch64\b", header)
            and re.search(r"Data:\s+2's complement, little endian", header)):
        raise ValueError(f"ERROR: not a genuine little-endian AArch64 ELF64: {path}")
    dyn = run("readelf", "-d", str(path))
    ver = run("readelf", "-V", str(path))
    if re.search(r"\(TEXTREL\)", dyn):
        raise ValueError(f"ERROR: TEXTREL in {path}")
    requirements = [tuple(map(int, parts)) for parts in VERSION.findall(ver)]
    if any(value > (2, 41) for value in requirements):
        raise ValueError(f"ERROR: GLIBC newer than 2.41 in {path}")
    return {
        "dynamic": sorted(DYN_META.findall(dyn)),
        "runpaths": PATH.findall(dyn),
        "glibc": sorted(requirements),
    }


def sanitize(stage: Path, output: Path):
    if not (stage/"usr/lib").is_dir():
        raise ValueError("ERROR: private SDK stage usr/lib missing")
    if output.exists() or output.is_symlink():
        raise ValueError("ERROR: output path already exists, refusing overwrite")
    if output.resolve().is_relative_to(stage.resolve()):
        raise ValueError("ERROR: refusing to write into source SDK")
    # Preflight every input before creating output, fail closed on other paths.
    sources = {}
    for name, expected in TARGETS.items():
        f = stage/"usr/lib"/name
        if not f.is_file() or f.is_symlink():
            raise ValueError(f"ERROR: expected regular source ELF missing: {f}")
        d = details(f)
        if d["runpaths"] not in ([("RUNPATH", expected)], [("RPATH", expected)]):
            raise ValueError(f"ERROR: unexpected build path in {name}: {d['runpaths']}")
        sources[name] = d
    (output/"usr/lib").mkdir(parents=True)
    report = []
    for name in TARGETS:
        src = stage/"usr/lib"/name
        dest = output/"usr/lib"/name
        shutil.copy2(src, dest)
        run("patchelf", "--remove-rpath", str(dest))
        amended = details(dest)
        original = sources[name]
        if amended["runpaths"] or amended["dynamic"] != original["dynamic"] or amended["glibc"] != original["glibc"]:
            raise ValueError(f"ERROR: ABI metadata changed unexpectedly: {name}")
        report.append({
            "file": name,
            "removed_build_path": original["runpaths"][0][1],
            "input_sha256": hashlib.sha256(src.read_bytes()).hexdigest(),
            "output_sha256": hashlib.sha256(dest.read_bytes()).hexdigest(),
            "static_check": "PASSED_NO_RPATH_SAME_SONAME_NEEDED_GLIBC",
        })
    (output/"report.json").write_text(json.dumps(report, indent=2) + "\n")
    return len(report)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--stage", type=Path, required=True)
    ap.add_argument("--output", type=Path, required=True)
    args = ap.parse_args()
    try:
        count = sanitize(args.stage.resolve(), args.output.resolve())
    except (ValueError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
        print(str(exc), file=sys.stderr)
        return 6
    print(f"CI_RPATH_REMOVED_LIBRARY_COPIES={count}")
    print("CI_RPATH_OVERLAY=PASS_STATIC_ABI_METADATA")
    print("R36H_INSTALLABLE=no")
    print("TARGET_EXECUTED=no")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
