#!/usr/bin/env python3
"""Read-only postmortem for one completed, real WPE 2.54.1 GCC15 build artifact.

Does not trust the conclusion supplied by a GitHub Actions workflow_run event;
the workflow must independently authenticate its source run first. This script
NEVER executes target ELF files, certifies a ROCKNIX device, or builds a ZIP.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
from pathlib import Path
import re
import sys

ELF_NAMES = (
    ("lib/libWPEWebKit-2.0.so.1", "WEBKIT"),
    ("libexec/wpe-webkit-2.0/WPEWebProcess", "WEB_PROCESS"),
    ("libexec/wpe-webkit-2.0/WPENetworkProcess", "NETWORK_PROCESS"),
    ("lib/wpe-webkit-2.0/injected-bundle/libWPEInjectedBundle.so", "INJECTED_BUNDLE"),
)
RESOURCE = "share/wpe-webkit-2.0/inspector.gresource"
MAX_RESULT = 16 * 1024


def import_elf_inspector():
    src = Path(__file__).with_name("audit-real-fourcc-wpe-artifacts.py")
    spec = importlib.util.spec_from_file_location("real_wpe_elf_postmortem", src)
    if spec is None or spec.loader is None:
        raise ValueError("ELF_AUDITOR_MODULE_NOT_FOUND")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.inspect


def safe_regular(root: Path, path: Path) -> bool:
    try:
        return (path.is_file() and not path.is_symlink() and path.stat().st_size > 0
                and path.resolve(strict=True).is_relative_to(root.resolve(strict=True)))
    except (OSError, RuntimeError):
        return False


def find_unique_dir(root: Path, name: str) -> Path | None:
    candidates = [p for p in root.rglob(name)
                  if p.is_dir() or p.is_symlink()]
    if len(candidates) > 1:
        raise ValueError("AMBIGUOUS_ARTIFACT_DIRECTORY:" + name)
    if candidates:
        directory = candidates[0]
        if directory.is_symlink() or not directory.resolve().is_relative_to(root.resolve()):
            raise ValueError("UNSAFE_ARTIFACT_DIRECTORY:" + name)
        return directory
    return None


def find_result(root: Path) -> Path | None:
    results = list(root.rglob("wpe-subprocesses-result.txt"))
    if len(results) > 1:
        raise ValueError("AMBIGUOUS_BUILD_RESULT")
    if results:
        if not safe_regular(root, results[0]):
            raise ValueError("UNSAFE_BUILD_RESULT")
        return results[0]
    return None


def read_build_status(root: Path) -> dict[str, str]:
    file = find_result(root)
    if file is None:
        return {}
    if file.stat().st_size > MAX_RESULT:
        raise ValueError("OVERSIZE_BUILD_RESULT")
    status = {}
    for line in file.read_text(encoding="utf-8", errors="replace").splitlines():
        if re.fullmatch(r"[A-Z0-9_]+=[A-Za-z0-9_,.-]+", line):
            key, value = line.split("=", 1)
            # The build report intentionally advances START -> BLOCKED/PASS.
            # All other duplicated contradictory fields remain suspicious.
            if key in status and status[key] != value and key != "WPE_SUBPROCESS_BUILD":
                raise ValueError("CONFLICTING_BUILD_RESULT:" + key)
            status[key] = value
    return status


def analyze(root: Path, conclusion: str, inspect_elf=None) -> str:
    if conclusion not in ("success", "failure"):
        raise ValueError("ONLY_COMPLETED_SUCCESS_OR_FAILURE")
    if not root.is_dir() or root.is_symlink():
        raise ValueError("INVALID_DOWNLOADED_ARTIFACT")
    inspect_elf = inspect_elf or import_elf_inspector()
    report = read_build_status(root)
    closed = find_unique_dir(root, "private-wpe-runtime-sdk-closed")
    staged = find_unique_dir(root, "private-wpe-runtime")
    runtime = closed or staged
    phase = ("CLOSED_SDK_RUNTIME" if closed else
             "UNBUNDLED_PRIVATE_RUNTIME" if staged else "NO_STAGED_RUNTIME")
    lines = [
        "WPE_UNIFIED_POSTMORTEM=READ_ONLY_STATIC_INSPECTION",
        "WPE_UNIFIED_SOURCE_CONCLUSION=" + conclusion,
        "WPE_UNIFIED_RUNTIME_SOURCE=" + phase,
        "WPE_UNIFIED_BUILD_RESULT=" + report.get("WPE_SUBPROCESS_BUILD", "NOT_REPORTED"),
        "WPE_UNIFIED_CMAKE_EXIT=" + report.get("WPE_SUBPROCESS_CMAKE_EXIT", "NOT_REPORTED"),
        "WPE_UNIFIED_ELF_EXECUTED=no",
        "WPE_UNIFIED_DEVICE_ABI_PROVEN=no",
        "WPE_UNIFIED_PIXELS_RENDERED_ON_R36H=no",
        "R36H_INSTALLABLE=no",
    ]
    valid = 0
    if runtime:
        for rel, key in ELF_NAMES:
            path = runtime / rel
            if not safe_regular(runtime, path):
                lines.append("WPE_UNIFIED_" + key + "=MISSING_OR_UNSAFE")
                continue
            findings = inspect_elf(path)
            if findings:
                lines.append("WPE_UNIFIED_" + key + "=REJECTED_ELF_STATIC")
                for item in sorted(set(findings))[:8]:
                    lines.append("WPE_UNIFIED_FINDING=" + key + ":" + item)
            else:
                valid += 1
                lines.append("WPE_UNIFIED_" + key + "=PASS_ELF_STATIC_ONLY")
                lines.append("WPE_UNIFIED_SHA256_" + key + "=" +
                             hashlib.sha256(path.read_bytes()).hexdigest())
        res = runtime / RESOURCE
        if safe_regular(runtime, res):
            lines.append("WPE_UNIFIED_INSPECTOR_RESOURCE=NONEMPTY_STATIC")
        else:
            lines.append("WPE_UNIFIED_INSPECTOR_RESOURCE=MISSING_OR_UNSAFE")
    else:
        for _, key in ELF_NAMES:
            lines.append("WPE_UNIFIED_" + key + "=NO_STAGED_RUNTIME")
        lines.append("WPE_UNIFIED_INSPECTOR_RESOURCE=NO_STAGED_RUNTIME")
    complete = (valid == len(ELF_NAMES) and runtime is not None
                and safe_regular(runtime, runtime / RESOURCE))
    # In a failed source workflow, these checks are purely forensic. The
    # packaging/release workflow must still reject conclusion != success.
    lines.append("WPE_UNIFIED_ALL_ASSETS_PRESENT_STATIC=" + ("yes" if complete else "no"))
    lines.append("WPE_UNIFIED_LINKED_BUT_WORKFLOW_FAILED=" + (
        "yes" if complete and conclusion == "failure" and
        report.get("WPE_SUBPROCESS_CMAKE_EXIT") == "0" else "no"))
    lines.append("WPE_UNIFIED_RELEASE_GATE=" +
                 ("FAILED_WORKFLOW_NO_RELEASE" if conclusion == "failure"
                  else "SEPARATE_ABI_AND_PACKAGING_GATES_REQUIRED"))
    return "\n".join(lines) + "\n"


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--artifact", required=True, type=Path)
    p.add_argument("--build-conclusion", required=True, choices=("success", "failure"))
    p.add_argument("--report", required=True, type=Path)
    a = p.parse_args()
    if not a.report.parent.is_dir() or a.report.is_symlink():
        p.error("existing safe report directory required")
    try:
        findings = analyze(a.artifact, a.build_conclusion)
        a.report.write_text(findings, encoding="utf-8")
        print(findings, end="")
    except (OSError, ValueError) as error:
        print("WPE_UNIFIED_POSTMORTEM=ERROR:" + str(error), file=sys.stderr)
        return 6
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
