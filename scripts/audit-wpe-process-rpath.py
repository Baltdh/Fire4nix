#!/usr/bin/env python3
"""Fail closed on nonportable RPATH/RUNPATH in *installed* ARM64 WPE subprocesses.

A CMake build-tree binary may reference SDK/build directories before install.
Only ELF files copied from the DESTDIR installation are release candidates.
This tool never rewrites a binary, installs a file or executes target code.
"""
from __future__ import annotations

import argparse
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys

RPATH = re.compile(r"\((?:RPATH|RUNPATH)\).*?\[([^\]]*)\]")
NEEDED = re.compile(r"\(NEEDED\).*?\[([^\]]*)\]")


def verify_dynamic(text: str) -> None:
    if not NEEDED.search(text):
        raise ValueError("MISSING_DYNAMIC_DEPENDENCIES")
    for value in RPATH.findall(text):
        for component in value.split(":"):
            if (not component
                    or component != "$ORIGIN" and not component.startswith("$ORIGIN/")
                    or ".." in PurePosixPath(component).parts):
                raise ValueError("NON_PORTABLE_INSTALLED_RPATH:" + component)


def verify_file(path: Path) -> None:
    if not path.is_file() or path.is_symlink() or not path.stat().st_size:
        raise ValueError("MISSING_OR_UNSAFE_INSTALLED_ELF")
    header = subprocess.run(
        ["readelf", "-h", str(path)], check=True, capture_output=True,
        text=True, timeout=30).stdout
    if not all(re.search(pattern, header) for pattern in (
        r"Class:\s+ELF64\b", r"Machine:\s+AArch64\b",
        r"Data:\s+2's complement, little endian")):
        raise ValueError("NOT_AARCH64_ELF64")
    dynamic = subprocess.run(
        ["readelf", "-d", str(path)], check=True, capture_output=True,
        text=True, timeout=30).stdout
    verify_dynamic(dynamic)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("installed_elf", type=Path)
    args = parser.parse_args()
    try:
        verify_file(args.installed_elf)
    except (OSError, ValueError, subprocess.CalledProcessError,
            subprocess.TimeoutExpired) as exc:
        print("WPE_INSTALLED_ELF_RPATH=BLOCKED:" + str(exc), file=sys.stderr)
        return 6
    print("WPE_INSTALLED_ELF_RPATH=PASS_RELOCATABLE_AARCH64")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
