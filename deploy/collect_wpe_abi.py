#!/usr/bin/env python3
"""Static ARM64 WPE ABI inventory; never executes the supplied ELF files.

Produces build-origin evidence, NOT an assertion of compatibility with a
ROCKNIX device. Only source-controlled paths and trusted CI build artifacts
should be passed to this tool.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys


PROCESSES = ("WPEWebProcess", "WPENetworkProcess", "WPEGPUProcess")
VERSION_PATTERN = re.compile(r"GLIBC_(\d+(?:\.\d+)+)")
NEEDED_PATTERN = re.compile(r"\(NEEDED\).*?\[(.*?)\]")
INTERPRETER_PATTERN = re.compile(r"Requesting program interpreter: (.*?)\]")
SONAME_PATTERN = re.compile(r"\(SONAME\).*?\[(.*?)\]")


def version_key(value):
    return tuple(int(x) for x in value.split("."))


def read_elf(path, expected_machine):
    if not path.is_file():
        raise ValueError(f"required ELF file missing: {path}")
    if path.is_symlink():
        raise ValueError(f"ELF symlink must be resolved explicitly: {path}")
    with path.open("rb") as stream:
        header = stream.read(20)
    if len(header) < 20 or header[:6] != b"\x7fELF\x02\x01":
        raise ValueError(f"not 64-bit little-endian ELF: {path}")
    machine = int.from_bytes(header[18:20], "little")
    if machine != expected_machine:
        raise ValueError(f"unexpected ELF e_machine {machine} at {path}; expected {expected_machine}")
    result = subprocess.run(
        ["readelf", "-h", "-d", "-V", "-l", str(path)],
        capture_output=True, text=True, check=False
    )
    if result.returncode:
        raise ValueError(f"readelf rejected {path}: {result.stderr.strip()}")
    output = result.stdout
    versions = sorted(set(VERSION_PATTERN.findall(output)), key=version_key)
    version_name = "GLIBC_" + versions[-1] if versions else None
    sha = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            sha.update(chunk)
    return {
        "filename": path.name,
        "path_in_build_environment": str(path),
        "sha256": sha.hexdigest(),
        "elf_machine": machine,
        "glibc_versions": ["GLIBC_" + x for x in versions],
        "highest_required_glibc": version_name,
        "interpreter": INTERPRETER_PATTERN.findall(output),
        "needed": sorted(set(NEEDED_PATTERN.findall(output))),
        "soname": SONAME_PATTERN.findall(output),
    }


def inventory(launcher, webkit, subprocess_dir, expected_machine=183):
    paths = {"launcher": launcher, "WPEWebKit": webkit}
    for process in PROCESSES:
        paths[process] = subprocess_dir / process
    records = {role: read_elf(path.resolve(), expected_machine) for role, path in paths.items()}
    versions = sorted(
        {version.removeprefix("GLIBC_")
         for record in records.values() for version in record["glibc_versions"]},
        key=version_key
    )
    return {
        "schema": "fire4nix-wpe-abi-v1",
        "qualification": "build-origin static ABI inventory only; ROCKNIX runtime, dynamic plugins and graphics unverified",
        "expected_elf_machine": expected_machine,
        "required_processes": list(PROCESSES),
        "highest_required_glibc_across_components": ("GLIBC_" + versions[-1]) if versions else None,
        "components": records,
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--launcher", type=Path, required=True)
    parser.add_argument("--webkit", type=Path, required=True)
    parser.add_argument("--process-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--expect-machine", type=int, default=183, help="AArch64=183, x86_64=62 (tests only)")
    args = parser.parse_args(argv)
    try:
        output = inventory(args.launcher, args.webkit, args.process_dir, args.expect_machine)
    except (ValueError, OSError) as e:
        print("WPE ABI audit FAILED: " + str(e), file=sys.stderr)
        return 1
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, indent=2, sort_keys=True) + "\n")
    print("WPE ABI inventory: " + str(args.output))
    print("Highest required glibc: " + str(output["highest_required_glibc_across_components"]))
    print("Target device compatibility: UNVERIFIED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
