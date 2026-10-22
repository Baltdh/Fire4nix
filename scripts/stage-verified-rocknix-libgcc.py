#!/usr/bin/env python3
"""Find and stage a verified ROCKNIX AArch64 libgcc_s.so.1 into PRIVATE CI overlay.

Does not install on target or patch the compiler sysroot. Intended to resolve
the missing SONAME finding in static stage-1 ELF audit, not to certify ABI.
"""
from pathlib import Path
import argparse
import hashlib
import re
import shutil
import subprocess


def readelf(*args):
    result = subprocess.run(["readelf", *map(str, args)], capture_output=True,
                            text=True, check=True, timeout=20)
    return result.stdout


def validate(file):
    h = readelf("-h", file)
    d = readelf("-d", file)
    v = readelf("-V", file)
    if not (re.search(r"Class:\s+ELF64", h)
            and re.search(r"Machine:\s+AArch64", h)
            and re.search(r"Data:\s+2's complement, little endian", h)):
        raise ValueError("not little-endian ELF64 AArch64")
    if not re.search(r"\(SONAME\).*\[libgcc_s\.so\.1\]", d):
        raise ValueError("wrong or missing libgcc SONAME")
    if re.search(r"\(RPATH\)|\(RUNPATH\)|\(TEXTREL\)", d):
        raise ValueError("unexpected RUNPATH/RPATH/TEXTREL")
    glibc = [tuple(map(int, m)) for m in re.findall(r"Name: GLIBC_(\d+)\.(\d+)", v)]
    if any(x > (2, 41) for x in glibc):
        raise ValueError("requires GLIBC above 2.41")
    return max(glibc) if glibc else None


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--toolchain", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    args = p.parse_args()
    root = args.toolchain.resolve()
    output = args.output.resolve()
    if not root.is_dir() or not (root / "bin/aarch64-rocknix-linux-gnu-gcc").is_file():
        p.error("expected genuine ROCKNIX cross-compiler root")
    if output == root or output.is_relative_to(root) or root.is_relative_to(output):
        p.error("output must be outside the original SDK")
    if output.exists() or output.is_symlink():
        p.error("refusing to overwrite output")
    gcc = root / "bin/aarch64-rocknix-linux-gnu-gcc"
    triplet = subprocess.run([str(gcc), "-dumpmachine"], text=True,
                             capture_output=True, check=True, timeout=15).stdout.strip()
    if triplet != "aarch64-rocknix-linux-gnu":
        p.error("cross compiler targets a different ABI")
    candidates = []
    for item in sorted(root.rglob("libgcc_s.so.1")):
        target = item.resolve()
        if not target.is_file() or not target.is_relative_to(root):
            continue
        try:
            glibc = validate(target)
        except (ValueError, subprocess.CalledProcessError) as error:
            print(f"REJECTED={item}:{error}")
            continue
        candidates.append((item, target, glibc))
    if not candidates:
        raise SystemExit("ERROR: no verified AArch64 libgcc_s.so.1 in SDK")
    fingerprints = {hashlib.sha256(target.read_bytes()).hexdigest()
                    for _, target, _ in candidates}
    if len(fingerprints) != 1:
        raise SystemExit("ERROR: multiple different runtime libgcc candidates; no automatic choice")
    source = candidates[0][1]
    dest = output / "usr/lib/libgcc_s.so.1"
    dest.parent.mkdir(parents=True)
    shutil.copy2(source, dest)
    validate(dest)
    print(f"TARGET_LIBGCC_SOURCE={source}")
    print(f"TARGET_LIBGCC_SHA256={next(iter(fingerprints))}")
    print(f"TARGET_LIBGCC_GLIBC_MAX={candidates[0][2]}")
    print("TARGET_LIBGCC_STAGE=PASS_ISOLATED_ARM64_ELF")
    print("R36H_INSTALLABLE=no")
    print("RUNTIME_ABI_COMPLETE=no")


if __name__ == "__main__":
    main()
