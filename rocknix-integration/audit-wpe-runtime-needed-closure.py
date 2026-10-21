#!/usr/bin/env python3
"""Read-only WPE runtime DT_NEEDED closure check versus *explicit* ROCKNIX rootfs.

A conservative check: a SONAME match is not proof of ABI compatibility.
No ldd/dlopen, no target execution, no filesystem writes.
"""
import argparse
import os
from pathlib import Path
import re
import subprocess
import sys

NEEDED = re.compile(r"\(NEEDED\).*\[([^\]]+)\]")
RPATH = re.compile(r"\((?:RUNPATH|RPATH)\).*\[([^\]]*)\]")
SONAME = re.compile(r"\(SONAME\).*\[([^\]]+)\]")


def elf_dynamic(path):
    out = subprocess.run(["readelf", "-d", str(path)], capture_output=True,
                         text=True, timeout=25)
    if out.returncode:
        raise ValueError(f"not a loadable ELF: {path}")
    return NEEDED.findall(out.stdout), RPATH.findall(out.stdout), SONAME.findall(out.stdout)


def find_objects(root):
    return [p for p in root.rglob("*") if p.is_file() and
            (".so" in p.name or p.name in
             {"WPEWebProcess", "WPENetworkProcess", "WPEGPUProcess"})]


def index_sonames(root):
    found = {}
    for directory in ("usr/lib", "usr/lib64", "lib", "lib64"):
        p = root / directory
        if not p.is_dir():
            continue
        for obj in p.rglob("*"):
            if obj.is_file() and ".so" in obj.name:
                found.setdefault(obj.name, []).append(obj)
    return found


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--runtime", type=Path, required=True)
    ap.add_argument("--rootfs", type=Path, required=True)
    opts = ap.parse_args()
    if not opts.runtime.is_dir() or not opts.rootfs.is_dir():
        ap.error("both runtime and ROCKNIX rootfs directories must exist")
    if opts.runtime.resolve() == opts.rootfs.resolve():
        ap.error("runtime and rootfs must be distinct")
    files = find_objects(opts.runtime)
    if not files:
        ap.error("runtime has no ELF library/process candidates")
    system = index_sonames(opts.rootfs)
    local = {p.name: p for p in files}
    missing, unsafe, malformed = [], [], []
    checked = 0
    for p in sorted(files):
        try:
            needs, paths, sonames = elf_dynamic(p)
        except ValueError:
            malformed.append(str(p.relative_to(opts.runtime)))
            continue
        checked += 1
        # Runtime cannot carry executable/linker escape paths such as /home/runner.
        for value in paths:
            for seg in value.split(":"):
                if seg.startswith("/") and not seg.startswith("/usr/lib"):
                    unsafe.append((str(p.relative_to(opts.runtime)), seg))
        for name in needs:
            if "/" in name or ".." in name:
                unsafe.append((str(p.relative_to(opts.runtime)), name))
            elif name not in local and name not in system:
                missing.append((str(p.relative_to(opts.runtime)), name))
    print(f"ELF_DYNAMIC_INSPECTED={checked}")
    print(f"ROOTFS_LIB_NAMES_INDEXED={len(system)}")
    for path, name in missing:
        print(f"MISSING_NEEDED={path}:{name}")
    for path, name in unsafe:
        print(f"UNSAFE_DYNAMIC_PATH={path}:{name}")
    for name in malformed:
        print(f"NOT_ELF={name}")
    print(f"MISSING_COUNT={len(missing)}")
    print(f"UNSAFE_COUNT={len(unsafe)}")
    print(f"MALFORMED_COUNT={len(malformed)}")
    if missing or unsafe or malformed:
        print("DT_NEEDED_CLOSURE=BLOCKED")
        return 6
    print("DT_NEEDED_CLOSURE=SONAME_PRESENT_ONLY_ABI_NOT_PROVEN")
    print("HARDWARE_COMPATIBILITY=NOT_VERIFIED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
