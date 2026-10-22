#!/usr/bin/env python3
"""Static ELF DT_NEEDED audit for the isolated Fire4Nix ROCKNIX build SDK.

This is NOT a runtime loader, linker test, firmware compatibility proof, or
a successful WebKit build. It never uses ldd/dlopen or runs target binaries.
"""
from __future__ import annotations
import argparse
from collections import Counter
from pathlib import Path
import re
import subprocess
import sys

NEEDED = re.compile(r"\(NEEDED\).*\[([^\]]+)\]")
RPATH = re.compile(r"\((?:RUNPATH|RPATH)\).*\[([^\]]*)\]")
GLIBC = re.compile(r"Name: GLIBC_(\d+)\.(\d+)")
SEARCH_DIRS = ("usr/lib", "lib", "usr/lib64", "lib64", "usr/lib/aarch64-rocknix-linux-gnu")


def readelf(flag: str, path: Path) -> str:
    result = subprocess.run(["readelf", flag, str(path)], text=True,
                            capture_output=True, timeout=25, check=False)
    if result.returncode:
        raise ValueError(f"READELF_FAILED={path}:{flag}")
    return result.stdout


def is_aarch64(header: str) -> bool:
    return bool(re.search(r"Class:\s+ELF64\b", header)
                and re.search(r"Machine:\s+AArch64\b", header)
                and re.search(r"Data:\s+2's complement, little endian", header))


def stage_candidates(root: Path):
    base = root / "usr/lib"
    if not base.is_dir():
        raise ValueError("STAGE_USR_LIB_MISSING")
    for p in sorted(base.rglob("*")):
        if p.is_file() and not p.is_symlink() and ".so" in p.name:
            yield p


def safe_index(root: Path) -> tuple[dict[str, Path], list[str]]:
    result: dict[str, Path] = {}
    unsafe = []
    root = root.resolve()
    for name in SEARCH_DIRS:
        folder = root / name
        if not folder.is_dir():
            continue
        for item in sorted(folder.rglob("*.so*")):
            if not item.is_file() and not item.is_symlink():
                continue
            real = item.resolve()
            if not real.is_relative_to(root) or not real.is_file():
                unsafe.append(str(item))
                continue
            # Prefer non-symlink local regular file when names are repeated.
            result.setdefault(item.name, item)
    return result, unsafe


def audit(stage: Path, sysroot: Path) -> dict:
    stage = stage.resolve()
    sysroot = sysroot.resolve()
    if stage == sysroot or stage == Path("/") or sysroot == Path("/"):
        raise ValueError("REFUSE_ROOT_OR_IDENTICAL_INPUTS")
    staged, escaped_stage = safe_index(stage)
    system, escaped_system = safe_index(sysroot)
    objects = list(stage_candidates(stage))
    if not objects:
        raise ValueError("NO_STAGED_SHARED_ELF")
    missing, invalid, unsafe_rpath, too_new, matched = [], [], [], [], []
    for obj in objects:
        relative = str(obj.relative_to(stage))
        try:
            header = readelf("-h", obj)
            if not is_aarch64(header):
                invalid.append(f"{relative}:WRONG_ELF_MACHINE_CLASS_OR_ENDIAN")
                continue
            dynamic = readelf("-d", obj)
            versions = readelf("-V", obj)
        except (ValueError, subprocess.TimeoutExpired) as exc:
            invalid.append(f"{relative}:{exc}")
            continue
        for maj, minor in GLIBC.findall(versions):
            if (int(maj), int(minor)) > (2, 41):
                too_new.append(f"{relative}:GLIBC_{maj}.{minor}")
        for path_list in RPATH.findall(dynamic):
            for segment in path_list.split(":"):
                if segment.startswith("/") and not segment.startswith("/usr/lib"):
                    unsafe_rpath.append(f"{relative}:{segment}")
                if "/../" in segment or segment.endswith("/.."):
                    unsafe_rpath.append(f"{relative}:{segment}")
        for dep in NEEDED.findall(dynamic):
            if "/" in dep or ".." in dep:
                unsafe_rpath.append(f"{relative}:DT_NEEDED={dep}")
            elif dep in staged:
                matched.append(f"{relative}:{dep}:STAGE")
            elif dep in system:
                matched.append(f"{relative}:{dep}:SYSROOT")
            else:
                missing.append(f"{relative}:{dep}")
    return {
        "STAGE_SHARED_ELFS": len(objects),
        "INDEXED_STAGE_ALIASES": len(staged),
        "INDEXED_SYSROOT_ALIASES": len(system),
        "RESOLVED_EDGES": len(matched),
        "RESOLVED_FROM_STAGE": sum(v.endswith(":STAGE") for v in matched),
        "RESOLVED_FROM_SYSROOT": sum(v.endswith(":SYSROOT") for v in matched),
        "MISSING_EDGES": len(missing),
        "MISSING_SONAME_UNIQUE": len(set(line.rsplit(":", 1)[-1] for line in missing)),
        "MISSING_SONAME_NAMES": sorted(set(line.rsplit(":", 1)[-1] for line in missing)),
        "INVALID_ELFS": len(invalid),
        "NEWER_GLIBC_REFERENCES": len(too_new),
        "UNSAFE_PATHS": len(unsafe_rpath) + len(escaped_stage) + len(escaped_system),
        "MISSING_NEEDED": sorted(set(missing)),
        "INVALID_ELF": invalid,
        "TOO_NEW_GLIBC": sorted(set(too_new)),
        "UNSAFE_RPATH_OR_NEEDED": unsafe_rpath,
        "ESCAPED_SYMLINK": escaped_stage + escaped_system,
        "VALIDATION_LIMIT": "SONAME_PRESENCE_ONLY_NO_SYMBOL_VERSION_OR_DEVICE_LOADER_PROOF",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", type=Path, required=True)
    parser.add_argument("--sysroot", type=Path, required=True)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--strict", action="store_true")
    args = parser.parse_args()
    if not args.stage.is_dir() or not args.sysroot.is_dir():
        parser.error("stage and sysroot must exist")
    try:
        record = audit(args.stage, args.sysroot)
    except ValueError as err:
        print(f"ELF_CLOSURE_AUDIT=ERROR:{err}", file=sys.stderr)
        return 4
    broken = sum(record[k] for k in ("MISSING_EDGES", "INVALID_ELFS",
                  "NEWER_GLIBC_REFERENCES", "UNSAFE_PATHS"))
    record["ELF_CLOSURE_AUDIT"] = ("SONAME_CANDIDATES_FOUND_ABI_NOT_PROVEN"
                                  if broken == 0 else "INCOMPLETE_REQUIRES_REVIEW")
    keys = ("STAGE_SHARED_ELFS", "INDEXED_STAGE_ALIASES",
            "INDEXED_SYSROOT_ALIASES", "RESOLVED_EDGES", "RESOLVED_FROM_STAGE",
            "RESOLVED_FROM_SYSROOT", "MISSING_EDGES", "MISSING_SONAME_UNIQUE",
            "MISSING_SONAME_NAMES", "INVALID_ELFS",
            "NEWER_GLIBC_REFERENCES", "UNSAFE_PATHS", "ELF_CLOSURE_AUDIT",
            "VALIDATION_LIMIT", "MISSING_NEEDED", "INVALID_ELF",
            "TOO_NEW_GLIBC", "UNSAFE_RPATH_OR_NEEDED", "ESCAPED_SYMLINK")
    lines = []
    for key in keys:
        value = record[key]
        if isinstance(value, list):
            lines.extend(f"{key}={item}" for item in value)
        else:
            lines.append(f"{key}={value}")
    content = "\n".join(lines) + "\n"
    sys.stdout.write(content)
    if args.report:
        if not args.report.parent.is_dir():
            parser.error("report parent directory must already exist")
        args.report.write_text(content)
    return 6 if broken and args.strict else 0


if __name__ == "__main__":
    sys.exit(main())
