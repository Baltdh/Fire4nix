#!/usr/bin/env python3
"""Inspect WPE 2.54.1 ARM64 library and process ELFs from private CI output.

Never execute target binaries. A successful build does not establish device ABI
or an installable browser. Failed builds must still yield useful diagnostics.
"""
from __future__ import annotations
import argparse
import hashlib
from pathlib import Path
import re
import subprocess
import sys

ARTIFACT_DIR = "compiled-target-evidence"
NAMES = ("libWPEWebKit-2.0.so.1", "WPEWebProcess", "WPENetworkProcess")
GLIBC_MAX = (2, 41)
# Accepted loader names for the RK3326 ROCKNIX AArch64 toolchain. This only
# validates ELF metadata, not that the user's physical firmware supplies it.
TARGET_INTERPRETERS = frozenset({
    "/lib/ld-linux-aarch64.so.1",
    "/lib64/ld-linux-aarch64.so.1",
    "/usr/lib/ld-linux-aarch64.so.1",
})
INTERP = re.compile(r"\[Requesting program interpreter:\s*([^\]]+)\]")
# GCC 15 AArch64 may emit outlined-atomics helpers that are not supplied
# by the pinned RK3326 runtime. Only undefined dynamic references are fatal:
# a local definition/export of the same symbol is not a dangling dependency.
OUTLINED_ATOMICS = re.compile(
    r"\b__aarch64_(?:cas|swp|ldadd|ldclr|ldset|ldeor)(?:p?[0-9])\w*(?:@|\b)")



def tool(flag: str, path: Path) -> str:
    return subprocess.run(["readelf", "--wide", flag, str(path)], check=True,
                          capture_output=True, text=True, timeout=30).stdout


def inspect(path: Path, read=tool) -> list[str]:
    findings = []
    if not path.is_file() or path.is_symlink() or path.stat().st_size < 100:
        return ["MISSING_OR_UNSAFE_ELF"]
    try:
        h = read("-h", path)
        d = read("-d", path)
        v = read("-V", path)
        sym = read("--dyn-syms", path)
        program_headers = read("-l", path) if path.name in NAMES[1:] else ""
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired, ValueError):
        return ["UNREADABLE_ELF"]
    expected = ((r"Class:\s+ELF64\b", "WRONG_CLASS"),
                (r"Machine:\s+AArch64\b", "WRONG_MACHINE"),
                (r"Data:\s+2's complement, little endian", "WRONG_ENDIAN"))
    for pattern, error in expected:
        if not re.search(pattern, h):
            findings.append(error)
    if not re.search(r"Type:\s+(?:DYN|EXEC)\b", h):
        findings.append("WRONG_ELF_TYPE")
    for a, b in re.findall(r"Name:\s*GLIBC_(\d+)\.(\d+)\b", v):
        if (int(a), int(b)) > GLIBC_MAX:
            findings.append(f"GLIBC_ABOVE_2_41:{a}.{b}")
    for part in re.findall(r"\((?:RUNPATH|RPATH)\).*?\[([^\]]*)\]", d):
        for segment in part.split(":"):
            if (not segment or
                not (segment == "$ORIGIN" or segment.startswith("$ORIGIN/")) or
                "/../" in segment or segment.endswith("/..")):
                findings.append("UNSAFE_RUNPATH:" + segment)
    for dep in re.findall(r"\(NEEDED\).*?\[([^\]]*)\]", d):
        if not dep or "/" in dep or ".." in dep:
            findings.append("UNSAFE_NEEDED:" + dep)
        if dep.startswith(("libgstreamer", "libgst")):
            findings.append("GSTREAMER_IN_MEDIA_FREE:" + dep)
    if any(re.search(r"\bUND\b", line) and
           re.search(r"\bGST_CAT_DEFAULT(?:@|\s|$)", line)
           for line in sym.splitlines()):
        findings.append("GST_CAT_DEFAULT_UNRESOLVED")
    for row in sym.splitlines():
        if re.search(r"\bUND\b", row):
            hit = OUTLINED_ATOMICS.search(row)
            if hit:
                findings.append("UNDEFINED_GCC15_OUTLINED_ATOMIC:" + hit.group(0).rstrip("@"))
    # DT_NEEDED alone does not establish that the handheld's ELF loader
    # can start the process. Require a supported ARM64 PT_INTERP for each
    # dynamic helper, while allowing genuinely static ELF executables.
    if path.name in NAMES[1:]:
        interp_paths = INTERP.findall(program_headers)
        if len(interp_paths) > 1:
            findings.append("AMBIGUOUS_PT_INTERP")
        elif not interp_paths:
            if re.search(r"\(NEEDED\)", d):
                findings.append("MISSING_DYNAMIC_PT_INTERP")
        elif interp_paths[0] not in TARGET_INTERPRETERS:
            findings.append("FOREIGN_PT_INTERP:" + interp_paths[0])
    if path.name == "libWPEWebKit-2.0.so.1":
        if not re.search(r"\(SONAME\).*?\[libWPEWebKit-2\.0\.so\.1\]", d):
            findings.append("WRONG_SONAME")
        if not any("webkit_web_view_get_wpe_view" in line
                   and not re.search(r"\bUND\b", line)
                   for line in sym.splitlines()):
            findings.append("MISSING_WPE_PLATFORM_ENTRYPOINT")
    return sorted(set(findings))


def evidence(root: Path, conclusion: str, read=tool) -> tuple[str, bool]:
    if conclusion not in ("success", "failure"):
        raise ValueError("only completed success/failure workflows are accepted")
    matches = sorted(root.rglob(ARTIFACT_DIR))
    matches = [p for p in matches if p.is_dir() and not p.is_symlink()]
    lines = [
        "SOURCE_BUILD_CONCLUSION=" + conclusion,
        "WPE_TARGET_BINARY_EXECUTED=no",
        "R36H_PHYSICAL_TEST_COMPLETED=no",
        "R36H_INSTALLABLE=no",
    ]
    if len(matches) != 1:
        lines.append(f"WPE_EVIDENCE_DIR_COUNT={len(matches)}")
        lines.append("WPE_LINKED_AND_PROCESSES_STATUS=NO_UNIQUE_EVIDENCE_DIRECTORY")
        return "\n".join(lines) + "\n", False
    folder = matches[0]
    errors = []
    for name in NAMES:
        file = folder / name
        if not file.is_file() or file.is_symlink():
            errors.append(f"{name}:MISSING")
            lines.append(f"WPE_ARTIFACT_{name}=MISSING")
            continue
        issues = inspect(file, read)
        if issues:
            errors.extend(f"{name}:{item}" for item in issues)
            lines.append(f"WPE_ARTIFACT_{name}=BLOCKED")
        else:
            lines.append(f"WPE_ARTIFACT_{name}=PASS_STATIC_AARCH64")
            lines.append(f"WPE_SHA256_{name}={hashlib.sha256(file.read_bytes()).hexdigest()}")
    lines.extend("WPE_BUILD_FINDING=" + finding for finding in errors)
    status = ("PASS_STATIC_ONLY_NOT_DEVICE_ABI" if not errors and conclusion == "success"
              else "BLOCKED_OR_INCOMPLETE")
    lines.append(f"WPE_LINKED_AND_PROCESSES_STATUS={status}")
    return "\n".join(lines) + "\n", status == "PASS_STATIC_ONLY_NOT_DEVICE_ABI"


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--artifact", required=True, type=Path)
    p.add_argument("--report", required=True, type=Path)
    p.add_argument("--build-conclusion", choices=("success", "failure"), required=True)
    args = p.parse_args()
    if not args.artifact.is_dir() or not args.report.parent.is_dir() or args.report.is_symlink():
        p.error("expected artifact tree and safe existing report directory")
    try:
        text, passed = evidence(args.artifact, args.build_conclusion)
    except (OSError, ValueError) as exc:
        print(f"WPE_ARTIFACT_AUDIT=ERROR:{type(exc).__name__}:{exc}", file=sys.stderr)
        return 4
    args.report.write_text(text, encoding="utf-8")
    print(text, end="")
    return 0 if passed or args.build_conclusion == "failure" else 6


if __name__ == "__main__":
    raise SystemExit(main())
