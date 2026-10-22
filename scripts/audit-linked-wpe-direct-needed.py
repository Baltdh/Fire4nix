#!/usr/bin/env python3
"""Inspect direct DT_NEEDED edges of an actually linked WPEWebKit ARM64 ELF.

The toolchain's ROCKNIX sysroot is NOT proof of the handheld's installed
firmware. Stage-1 SDK libraries are build-only, never assumed on the device.
No ldd, loader, dynamic linking or target executable is run.
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

NEEDED = re.compile(r"\(NEEDED\).*?\[([^\]]+)\]")
VERSIONS = re.compile(r"Name:\s*GLIBC_(\d+)\.(\d+)\b")
SEARCH = ("usr/lib", "lib", "usr/lib64", "lib64",
          "usr/lib/aarch64-rocknix-linux-gnu")
TARGET_GLIBC = (2, 41)


def readelf(flag: str, path: Path) -> str:
    p = subprocess.run(["readelf", "--wide", flag, str(path)],
                       check=True, capture_output=True, text=True, timeout=30)
    return p.stdout


def check_arch(header: str) -> bool:
    return all(re.search(s, header) for s in (
        r"Class:\s+ELF64\b", r"Machine:\s+AArch64\b",
        r"Data:\s+2's complement, little endian"))


def index_libs(root: Path) -> dict[str, Path]:
    result = {}
    real_root = root.resolve()
    for folder in SEARCH:
        d = root / folder
        if not d.is_dir():
            continue
        for file in sorted(d.rglob("*.so*")):
            if not file.is_file() and not file.is_symlink():
                continue
            # A symlink may be valid within the SDK, but must not escape.
            try:
                resolved = file.resolve(strict=True)
            except (OSError, RuntimeError):
                continue
            if resolved.is_file() and resolved.is_relative_to(real_root):
                result.setdefault(file.name, file)
    return result


def audit(library: Path, sysroot: Path, stage: Path, elf=readelf) -> dict:
    if library.is_symlink() or not library.is_file():
        raise ValueError("LINKED_WPE_ELF_REQUIRED")
    if library.name != "libWPEWebKit-2.0.so.1":
        raise ValueError("WRONG_WPE_LIBRARY_BASENAME")
    if not check_arch(elf("-h", library)):
        raise ValueError("WPE_LIBRARY_FOREIGN_ARCH")
    dynamic = elf("-d", library)
    if not re.search(r"\(SONAME\).*?\[libWPEWebKit-2\.0\.so\.1\]", dynamic):
        raise ValueError("WPE_SONAME_MISMATCH")
    dependencies = NEEDED.findall(dynamic)
    if not dependencies:
        raise ValueError("NO_WPE_DYNAMIC_DEPENDENCIES")

    system = index_libs(sysroot)
    staged = index_libs(stage)
    source = []
    missing = []
    stage_only = []
    invalid = []
    seen = set()
    for name in dependencies:
        if name in seen:
            invalid.append("DUPLICATE_NEEDED:" + name)
            continue
        seen.add(name)
        if not name or "/" in name or ".." in name:
            invalid.append("UNSAFE_NEEDED:" + name)
            continue
        if name.startswith(("libgst", "libgstreamer")):
            invalid.append("GSTREAMER_IN_MEDIA_FREE:" + name)
            continue
        if name in system:
            kind, provider = "SYSROOT", system[name]
        elif name in staged:
            kind, provider = "SDK_STAGE_BUNDLE_REQUIRED", staged[name]
            stage_only.append(name)
        else:
            missing.append(name)
            continue
        try:
            header = elf("-h", provider)
            glibc_versions = elf("-V", provider)
            if not check_arch(header):
                invalid.append("PROVIDER_WRONG_ARCH:" + name)
                continue
            if any((int(a), int(b)) > TARGET_GLIBC
                   for a, b in VERSIONS.findall(glibc_versions)):
                invalid.append("PROVIDER_GLIBC_ABOVE_2_41:" + name)
                continue
        except (OSError, subprocess.CalledProcessError,
                subprocess.TimeoutExpired, ValueError):
            invalid.append("PROVIDER_NOT_VALIDATED:" + name)
            continue
        source.append((name, kind))

    state = ("BLOCKED" if invalid or missing else
             "STAGE_LIBRARIES_MUST_BE_BUNDLED" if stage_only
             else "DIRECT_SONAMES_PRESENT_IN_TOOLCHAIN_SYSROOT")
    return {
        "WPE_DIRECT_ELF_NEEDED_STATUS": state,
        "WPE_DIRECT_ELF_NEEDED_COUNT": len(dependencies),
        "WPE_DIRECT_SYSROOT_EDGES": sum(1 for _, loc in source if loc == "SYSROOT"),
        "WPE_DIRECT_SDK_BUNDLE_EDGES": len(stage_only),
        "WPE_DIRECT_MISSING_EDGES": len(missing),
        "WPE_DIRECT_INVALID_EDGES": len(invalid),
        "WPE_DIRECT_SOURCE": [f"{name}:{location}" for name, location in source],
        "WPE_DIRECT_BUNDLE_REQUIRED": sorted(set(stage_only)),
        "WPE_DIRECT_MISSING": sorted(set(missing)),
        "WPE_DIRECT_INVALID": sorted(set(invalid)),
        "R36H_FIRMWARE_SONAMES_VERIFIED": "no",
        "WPE_TRANSITIVE_DEPENDENCY_CLOSURE_VERIFIED": "no",
        "R36H_INSTALLABLE": "no",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--library", type=Path, required=True)
    parser.add_argument("--sysroot", type=Path, required=True)
    parser.add_argument("--sdk-stage", type=Path, required=True)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--strict", action="store_true")
    args = parser.parse_args()
    if not args.sysroot.is_dir() or not args.sdk_stage.is_dir():
        parser.error("target sysroot and stage directories required")
    try:
        result = audit(args.library, args.sysroot, args.sdk_stage)
    except (OSError, ValueError, subprocess.CalledProcessError,
            subprocess.TimeoutExpired) as exc:
        print(f"WPE_DIRECT_ELF_NEEDED_STATUS=ERROR:{type(exc).__name__}:{exc}",
              file=sys.stderr)
        return 4
    lines = []
    for key, value in result.items():
        if isinstance(value, list):
            lines.extend(f"{key}={x}" for x in value)
        else:
            lines.append(f"{key}={value}")
    out = "\n".join(lines) + "\n"
    print(out, end="")
    if args.report:
        if not args.report.parent.is_dir() or args.report.is_symlink():
            parser.error("report parent missing or unsafe")
        args.report.write_text(out)
    return 6 if args.strict and result["WPE_DIRECT_ELF_NEEDED_STATUS"] == "BLOCKED" else 0


if __name__ == "__main__":
    raise SystemExit(main())
