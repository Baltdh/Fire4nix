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
           "wpe-subprocesses-stage.log", "wpe-sdk-dependency-bundle.log",
           "wpe-runtime-closure.log")
# The genuine build script records the exact failing phase before returning.
# Read its markers first: old compiler errors in a successful compilation
# must not shadow the NEW failure in installation, staging or SDK bundling.
PHASES = (
    ("WPE_PRIVATE_RUNTIME_CLOSURE", "ELF_CLOSURE", "wpe-runtime-closure.log"),
    ("WPE_PRIVATE_RUNTIME_SDK_DEPENDENCIES", "SDK_BUNDLE",
     "wpe-sdk-dependency-bundle.log"),
    ("WPE_PRIVATE_RUNTIME_STAGE", "RUNTIME_STAGE", "wpe-subprocesses-stage.log"),
    ("WPE_PRIVATE_DESTDIR_INSTALL", "CMAKE_INSTALL", "wpe-subprocesses-install.log"),
)
PHASE_FAILURE_CLASSES = {
    "ELF_CLOSURE": "TRANSITIVE_ELF_CLOSURE_FAILURE",
    "SDK_BUNDLE": "SDK_DEPENDENCY_BUNDLE_FAILURE",
    "RUNTIME_STAGE": "RUNTIME_STAGING_FAILURE",
    "CMAKE_INSTALL": "CMAKE_INSTALL_FAILURE",
}
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
PIPELINE_ERROR = re.compile(
    r"(?i)error:|exception:|traceback|failed:|missing|required|not found|"
    r"could not|cannot find|blocked|no such file|valueerror|runtimeerror|"
    r"permission denied|symbol.*unresolved|SONAME|GLIBC_ABOVE"
)


def parse_result_status(raw: bytes) -> tuple[str, str, str]:
    # A duplicate conflicting exit code is not an authoritative diagnosis.
    # START -> BLOCKED or PASS is normal, but two different completed states
    # are not. Only allow documented ASCII status tokens, never eval or source.
    values: dict[str, list[str]] = {}
    for line in raw.decode("utf-8", errors="replace").splitlines():
        if re.fullmatch(r"[A-Z0-9_]+=[A-Za-z0-9_,.-]+", line):
            key, value = line.split("=", 1)
            values.setdefault(key, []).append(value)
    exit_codes = values.get("WPE_SUBPROCESS_CMAKE_EXIT", [])
    if len(set(exit_codes)) > 1:
        raise ValueError("CONFLICTING_WPE_CMAKE_EXIT")
    phases = [(name, phase, log) for name, phase, log in PHASES
              if any(v == "BLOCKED" or v == "STAGE_ONLY_DEPS_NOT_PACKAGED"
                     for v in values.get(name, []))]
    if len(phases) > 1:
        raise ValueError("CONFLICTING_WPE_FAILURE_PHASES")
    if phases:
        return phases[0][1], phases[0][2], exit_codes[0] if exit_codes else "NOT_REPORTED"
    if exit_codes and exit_codes[0] != "0":
        return "COMPILER_OR_LINKER", "wpe-subprocesses-build.log", exit_codes[0]
    if "BLOCKED" in values.get("WPE_SUBPROCESS_BUILD", []):
        return "COMPILER_OR_LINKER", "wpe-subprocesses-build.log", exit_codes[0] if exit_codes else "NOT_REPORTED"
    if "PASS_REAL_AARCH64" in values.get("WPE_SUBPROCESS_BUILD", []):
        return "NO_FAILURE_REPORTED", "none", exit_codes[0] if exit_codes else "NOT_REPORTED"
    return "UNDETERMINED", "none", exit_codes[0] if exit_codes else "NOT_REPORTED"



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
    phase, phase_log, exit_code = ("UNDETERMINED", "none", "NOT_REPORTED")
    if status_path:
        raw = status_path.read_bytes()
        if len(raw) > 8192:
            raise ValueError("BUILD_STATUS_TOO_LARGE")
        phase, phase_log, exit_code = parse_result_status(raw)
        if exit_code != "NOT_REPORTED":
            lines.append("WPE_BUILD_REPORTED_EXIT=" + exit_code)
    lines.append("WPE_FAILURE_PHASE=" + phase)
    lines.append("WPE_FAILURE_PHASE_LOG=" + phase_log)
    first_error = None
    classification = "NO_FAILURE_REPORTED" if phase == "NO_FAILURE_REPORTED" else "UNDETERMINED"
    selected = "none"
    # The phase-specific log is authoritative when a prior step has succeeded.
    # Preserve legacy first-error heuristics if the build result was not saved.
    order = (() if phase == "NO_FAILURE_REPORTED" else
             (phase_log,) if phase_log != "none" else REPORTS)
    for filename in order:
        path = found[filename]
        if path is None:
            continue
        if path.stat().st_size > MAX_LOG_BYTES:
            lines.append("WPE_LOG_OVERSIZE=" + filename)
            continue
        selected = filename
        body = path.read_text(encoding="utf-8", errors="replace")
        candidates = [line for line in body.splitlines()
                      if START.search(line) or (phase in PHASE_FAILURE_CLASSES
                                                and PIPELINE_ERROR.search(line))]
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
            if phase in PHASE_FAILURE_CLASSES:
                classification = PHASE_FAILURE_CLASSES[phase]
            elif FOURCC.search(first_error):
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
    if phase in PHASE_FAILURE_CLASSES:
        # A failing stage with an empty log is still a confirmed failure.
        classification = PHASE_FAILURE_CLASSES[phase]
        selected = phase_log
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
