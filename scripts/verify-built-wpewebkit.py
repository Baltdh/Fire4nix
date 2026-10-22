#!/usr/bin/env python3
"""Static readelf gate for an actually linked WPE WebKit AArch64 library.

This is *not* a dynamic loader, linker, TLS or physical R36H verification.
It must never execute or install the target binary.
"""
from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import re
import subprocess
import sys

SONAME = "libWPEWebKit-2.0.so.1"
ABI_MAX = (2, 41)


def inspect_elf(header: str, dynamic: str, versions: str, symbols: str) -> dict[str, str]:
    problems: list[str] = []
    expected = (
        (r"Class:\s*ELF64\b", "NOT_ELF64"),
        (r"Machine:\s*AArch64\b", "NOT_AARCH64"),
        (r"Data:\s*2's complement, little endian", "NOT_LITTLE_ENDIAN"),
        (r"Type:\s*DYN\b", "NOT_SHARED_ELF"),
    )
    for regex, message in expected:
        if not re.search(regex, header):
            problems.append(message)
    if not re.search(r"\(SONAME\).*\[libWPEWebKit-2\.0\.so\.1\]", dynamic):
        problems.append("WRONG_OR_MISSING_SONAME")
    if re.search(r"\(TEXTREL\)", dynamic):
        problems.append("TEXTREL_NOT_ALLOWED")
    if not any("webkit_web_view_get_wpe_view" in line and not re.search(r"\bUND\b", line)
               for line in symbols.splitlines()):
        problems.append("MISSING_WPE_PLATFORM_ENTRYPOINT")
    if any(re.search(r"\bUND\b", line) and re.search(r"GST_CAT_DEFAULT(?:@|\s|$)", line)
           for line in symbols.splitlines()):
        problems.append("UNDEFINED_GST_CAT_DEFAULT")
    dependencies = re.findall(r"\(NEEDED\).*\[([^\]]+)\]", dynamic)
    if not dependencies:
        problems.append("NO_DYNAMIC_DEPENDENCIES")
    for dependency in dependencies:
        if "/" in dependency or dependency == "" or ".." in dependency:
            problems.append("UNSAFE_DT_NEEDED")
        if dependency.startswith(("libgst", "libgstreamer")):
            problems.append("GSTREAMER_DEPENDENCY_IN_MEDIA_FREE_BUILD")
    for pathlist in re.findall(r"\((?:RUNPATH|RPATH)\).*\[([^\]]*)\]", dynamic):
        for part in pathlist.split(":"):
            # Runtime packages can use $ORIGIN-relative paths, not CI absolute
            # paths. Empty entries search the current working directory.
            if not (part == "$ORIGIN" or part.startswith("$ORIGIN/")):
                problems.append("NONRELOCATABLE_RPATH")
            if part == "" or "/../" in part or part.endswith("/.."):
                problems.append("UNSAFE_RPATH")
    glibc = [tuple(map(int, x)) for x in re.findall(r"Name:\s*GLIBC_(\d+)\.(\d+)\b", versions)]
    highest = max(glibc, default=(0, 0))
    if highest > ABI_MAX:
        problems.append("GLIBC_ABOVE_2_41")
    return {
        "WPE_LIBRARY_SONAME": SONAME,
        "WPE_LIBRARY_NEEDED_COUNT": str(len(dependencies)),
        "WPE_PLATFORM_EXPORT_PRESENT": str("MISSING_WPE_PLATFORM_ENTRYPOINT" not in problems).lower(),
        "WPE_MEDIA_FREE": str(not any(problem in problems for problem in
                                ("UNDEFINED_GST_CAT_DEFAULT", "GSTREAMER_DEPENDENCY_IN_MEDIA_FREE_BUILD"))).lower(),
        "WPE_LIBRARY_GLIBC_MAX": ".".join(map(str, highest)),
        "WPE_LIBRARY_ISSUES": ",".join(sorted(set(problems))) or "none",
        "WPE_LIBRARY_ELF_AUDIT": "PASS_STATIC_AARCH64" if not problems else "BLOCKED",
        "WPE_ABI_PROVEN_ON_R36H": "no",
        "R36H_INSTALLABLE": "no",
    }


def run_readelf(flag: str, path: Path) -> str:
    return subprocess.run(["readelf", "--wide", flag, str(path)], check=True, timeout=50,
                          capture_output=True, text=True).stdout


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--library", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    path = args.library
    if not path.is_file() or path.is_symlink() or not path.name.startswith("libWPEWebKit-2.0.so"):
        parser.error("expected a real, regular linked WPEWebKit library")
    if path.stat().st_size < 1024:
        parser.error("suspiciously small WebKit shared object")
    if not args.report.parent.is_dir() or args.report.is_symlink():
        parser.error("report directory must exist and report cannot be a symlink")
    try:
        record = inspect_elf(run_readelf("-h", path),
                             run_readelf("-d", path),
                             run_readelf("--version-info", path),
                             run_readelf("--dyn-syms", path))
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
        print(f"WPE_LIBRARY_ELF_AUDIT=ERROR:{type(exc).__name__}", file=sys.stderr)
        return 4
    sha = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            sha.update(block)
    record["WPE_LIBRARY_SHA256"] = sha.hexdigest()
    record["WPE_LIBRARY_SIZE_BYTES"] = str(path.stat().st_size)
    result = "\n".join(f"{k}={v}" for k, v in record.items()) + "\n"
    args.report.write_text(result, encoding="utf-8")
    sys.stdout.write(result)
    return 0 if record["WPE_LIBRARY_ELF_AUDIT"] == "PASS_STATIC_AARCH64" else 6


if __name__ == "__main__":
    raise SystemExit(main())
