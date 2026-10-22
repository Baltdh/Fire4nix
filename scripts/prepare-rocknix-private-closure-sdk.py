#!/usr/bin/env python3
"""Prepare *private* ROCKNIX SDK ELF closure: audited RPATH overlay + GCC libgcc.

This never overwrites the downloaded stage-1 SDK or edits device firmware.
Passing SONAME closure is NOT proof of symbol ABI, GPU or a working browser.
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

EXPECTED = ("libfontconfig.so", "libfontconfig.so.1", "libfontconfig.so.1.16.1",
            "libgcrypt.so", "libgcrypt.so.20", "libgcrypt.so.20.5.1")


def digest(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def elf(*args) -> str:
    result = subprocess.run(["readelf", *map(str, args)], capture_output=True,
                            text=True, check=True, timeout=30)
    return result.stdout


def prepare(stage: Path, overlay: Path, support: Path, out: Path) -> None:
    if out.exists() or out.is_symlink():
        raise ValueError("refuse to overwrite previous closure SDK")
    if stage.resolve() == out.resolve() or out.resolve().is_relative_to(stage.resolve()):
        raise ValueError("refuse to write into original SDK")
    data = json.loads((overlay/"report.json").read_text())
    if {row["file"] for row in data} != set(EXPECTED) or len(data) != 6:
        raise ValueError("unrecognized or incomplete sanitized overlay manifest")
    for row in data:
        name = row["file"]
        src = stage/"usr/lib"/name
        fixed = overlay/"usr/lib"/name
        if not src.is_file() or not fixed.is_file():
            raise ValueError(f"missing SDK or overlay source {name}")
        if digest(src) != row["input_sha256"] or digest(fixed) != row["output_sha256"]:
            raise ValueError(f"SHA256 mismatch for validated original or overlay: {name}")
        if row["static_check"] != "PASSED_NO_RPATH_SAME_SONAME_NEEDED_GLIBC":
            raise ValueError("overlay is not statically ABI-audited")
    if support.name != "libgcc_s.so.1" or not support.is_file():
        raise ValueError("expected pinned ROCKNIX libgcc_s.so.1 source only")
    header = elf("-h", support)
    if not (re.search(r"Class:\s+ELF64\b", header)
            and re.search(r"Machine:\s+AArch64\b", header)
            and re.search(r"Data:\s+2's complement, little endian", header)):
        raise ValueError("target GCC support is not ELF64 AArch64 little endian")
    dynamic = elf("-d", support)
    if not re.search(r"\(SONAME\).*\[libgcc_s\.so\.1\]", dynamic):
        raise ValueError("target GCC runtime SONAME mismatch")
    if re.search(r"\((RPATH|RUNPATH|TEXTREL)\)", dynamic):
        raise ValueError("unsafe target GCC runtime dynamic path or TEXTREL")
    versions = elf("-V", support)
    for major, minor in re.findall(r"Name: GLIBC_(\d+)\.(\d+)", versions):
        if (int(major), int(minor)) > (2, 41):
            raise ValueError(f"libgcc_s demands GLIBC_{major}.{minor} > 2.41")
    if (stage/"usr/lib/libgcc_s.so.1").exists():
        raise ValueError("unexpected duplicate GCC support already in stage")
    # The source SDK is immutable. The output is a disposable CI development tree.
    shutil.copytree(stage, out, symlinks=True)
    for name in EXPECTED:
        shutil.copy2(overlay/"usr/lib"/name, out/"usr/lib"/name)
    shutil.copy2(support, out/"usr/lib/libgcc_s.so.1")
    if digest(out/"usr/lib/libgcc_s.so.1") != digest(support):
        raise ValueError("target libgcc checksum changed during copy")
    for name in EXPECTED:
        if digest(out/"usr/lib"/name) != digest(overlay/"usr/lib"/name):
            raise ValueError(f"target patch checksum changed: {name}")
    print("ROCKNIX_PRIVATE_ELF_OVERLAY=PASS_6_RUNPATH_CLEAN_LIBRARIES")
    print("ROCKNIX_TARGET_LIBGCC=PASS_ELF64_AARCH64_GLIBC_MAX_2_41")
    print("ROCKNIX_PRIVATE_SDK=ASSEMBLED_FOR_STRICT_NEEDED_CHECK")
    print("TARGET_EXECUTED=no")
    print("R36H_INSTALLABLE=no")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--stage", type=Path, required=True)
    p.add_argument("--overlay", type=Path, required=True)
    p.add_argument("--support", type=Path, required=True)
    p.add_argument("--out", type=Path, required=True)
    a = p.parse_args()
    try:
        prepare(a.stage, a.overlay, a.support, a.out)
    except (ValueError, OSError, subprocess.CalledProcessError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 6
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
