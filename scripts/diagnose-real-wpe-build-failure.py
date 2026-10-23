#!/usr/bin/env python3
"""Diagnose the first real ROCKNIX WPE 2.54.1 compile/link error.

Read downloaded, private GitHub Actions artifacts. Never execute target ELFs,
infer device compatibility, or expose complete compiler commands in reports.
"""
from __future__ import annotations
import argparse
from pathlib import Path
import re
import sys

REPORTS = ("wpe-subprocesses-build.log", "wpe-subprocesses-install.log",
           "wpe-subprocesses-stage.log", "wpe-runtime-closure.log")
STATUS = "wpe-subprocesses-result.txt"
MAX_LOG_BYTES = 32 * 1024 * 1024
MAX_EXCERPT = 240
START = re.compile(
    r"FAILED:|fatal error:|(?<![\w])error:|undefined reference|"
    r"ninja: build stopped|collect2: error:|ld(?:\.lld)?: error:|"
    r"cannot find -l|Killed signal|out of memory|cannot allocate memory|"
    r"fatal:|WPE_RUNTIME_CLOSURE=BLOCKED", re.I)
LINK = re.compile(r"undefined reference|collect2: error|ld(?:\.lld)?: error|cannot find -l", re.I)
RESOURCE = re.compile(r"Killed signal|out of memory|cannot allocate memory", re.I)
FOURCC = re.compile(r"DRM_FORMAT_XRGB8888.*(?:not declared|undeclared|unknown)", re.I)


def safe_file(root: Path, path: Path) -> bool:
    try:
        return (path.is_file() and not path.is_symlink()
                and path.resolve(strict=True).is_relative_to(root.resolve(strict=True)))
    except (OSError, RuntimeError):
        return False


def find_report(root: Path, filename: str) -> Path | None:
    # The actual workflow uses wpe-unified-sdk-build/report, while GitHub's
    # artifact download flattens away its common parent. Permit either.
    matches = [p for p in root.rglob(filename) if p.parent.name == "report"
               and safe_file(root, p)]
    if len(matches) > 1:
        raise ValueError("AMBIGUOUS_BUILD_REPORT:" + filename)
    return matches[0] if matches else None


def analyze(root: Path) -> str:
    if not root.is_dir() or root.is_symlink():
        raise ValueError("INVALID_ARTIFACT_DIRECTORY")
    found = {}
    for filename in REPORTS + (STATUS,):
        found[filename] = find_report(root, filename)
    lines = ["WPE_REAL_BUILD_LOG_ANALYSIS=STATIC_ONLY",
             "WPE_TARGET_EXECUTED=no", "R36H_INSTALLABLE=no"]
    status_path = found[STATUS]
    if status_path:
        raw = status_path.read_bytes()
        if len(raw) > 8192:
            raise ValueError("BUILD_STATUS_TOO_LARGE")
        exit_codes = re.findall(rb"^WPE_SUBPROCESS_CMAKE_EXIT=(\d+)$", raw, re.M)
        if len(exit_codes) == 1:
            lines.append("WPE_BUILD_REPORTED_EXIT=" + exit_codes[0].decode("ascii"))
    first_error = None
    classification = "UNDETERMINED"
    selected = "none"
    for filename in REPORTS:
        path = found[filename]
        if path is None:
            continue
        if path.stat().st_size > MAX_LOG_BYTES:
            lines.append("WPE_LOG_OVERSIZE=" + filename)
            continue
        selected = filename
        body = path.read_text(encoding="utf-8", errors="replace")
        candidates = [line for line in body.splitlines() if START.search(line)]
        # Ninja prints FAILED target before the actual error. Prefer the
        # compiler/linker diagnosis; strip path/command details from output.
        detailed = [line for line in candidates if
                    ("error:" in line.lower() or "undefined reference" in line.lower()
                     or "cannot find -l" in line.lower() or RESOURCE.search(line))]
        if detailed:
            first_error = detailed[0]
        elif candidates:
            first_error = candidates[0]
        if first_error is not None:
            if FOURCC.search(first_error):
                classification = "WPE_2541_DRM_FOURCC_SOURCE"
            elif LINK.search(first_error):
                classification = "ELF_LINK_FAILURE"
            elif RESOURCE.search(first_error):
                classification = "RUNNER_RESOURCE_FAILURE"
            elif "fatal error:" in first_error.lower():
                classification = "COMPILER_FATAL_ERROR"
            else:
                classification = "BUILD_OR_RUNTIME_ERROR"
            break
    lines.append("WPE_DIAGNOSTIC_SOURCE=" + selected)
    lines.append("WPE_FAILURE_CLASS=" + classification)
    # Never include raw paths, compiler flags or other potentially private
    # metadata from a CI artifact in the GitHub summary. Only public hints
    # and line category are necessary to decide which source file to inspect.
    if first_error is None:
        lines.append("WPE_FIRST_ERROR_PRESENT=no")
    else:
        lines.append("WPE_FIRST_ERROR_PRESENT=yes")
        sanitized = first_error.rsplit("/", 1)[-1]
        sanitized = re.sub(r"[\x00-\x1f\x7f]+", " ", sanitized)
        lines.append("WPE_FIRST_ERROR_HINT=" + sanitized[:MAX_EXCERPT])
    return "\n".join(lines) + "\n"


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--artifact", required=True, type=Path)
    p.add_argument("--report", required=True, type=Path)
    args = p.parse_args()
    if not args.report.parent.is_dir() or args.report.is_symlink():
        p.error("safe report parent required")
    try:
        output = analyze(args.artifact)
        args.report.write_text(output, encoding="utf-8")
    except (OSError, ValueError) as exc:
        print("WPE_REAL_BUILD_LOG_ANALYSIS=ERROR:" + str(exc), file=sys.stderr)
        return 4
    print(output, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
