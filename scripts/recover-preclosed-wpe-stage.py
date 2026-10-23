#!/usr/bin/env python3
"""Recover only SHA-verified WPE preclosure stage from a pinned Actions artifact.

The original source run may have failed AFTER installing WPE but BEFORE bundling
libatomic. This tool never fabricates a library or a success report: it copies
only the authentic stage and recovers a missing SONAME alias by exact SHA256.
It does not execute target code or claim R36H hardware compatibility.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import os
from pathlib import Path
import shutil
import sys
import tempfile

SCRIPT = Path(__file__).resolve().with_name("materialize-wpe-artifact-sonames.py")
spec = importlib.util.spec_from_file_location("fire4nix_sha256_materializer", SCRIPT)
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)

LAYOUTS = ("private-wpe-runtime", "wpe-unified-sdk-build/private-wpe-runtime")
REQUIRED = (
    "BUILD-REPORT.txt", "SHA256SUMS.txt",
    "lib/libWPEWebKit-2.0.so.1",
    "libexec/wpe-webkit-2.0/WPEWebProcess",
    "libexec/wpe-webkit-2.0/WPENetworkProcess",
    "lib/wpe-webkit-2.0/injected-bundle/libWPEInjectedBundle.so",
    "share/wpe-webkit-2.0/inspector.gresource",
)
PROOF_LINES = (
    "GPU_PROCESS_PROFILE=disabled_verified_wayland",
    "WPE_INSTALLED_ASSETS_PROFILE=strict",
    "WPE_INSTALLED_ASSETS_STATUS=copied_and_static_elf_checked",
)

def verify_source(download: Path) -> Path:
    if not download.is_dir() or download.is_symlink():
        raise ValueError("INVALID_WPE_ARTIFACT_ROOT")
    matches = []
    for rel in LAYOUTS:
        p = download / rel
        if p.exists() or p.is_symlink():
            if p.is_symlink() or not p.is_dir() or not p.resolve(strict=True).is_relative_to(download.resolve()):
                raise ValueError("INVALID_WPE_ARTIFACT_LAYOUT")
            if any(parent.is_symlink() for parent in p.parents if parent != download):
                raise ValueError("SYMLINKED_WPE_ARTIFACT_PARENT")
            matches.append(p)
    if len(matches) != 1:
        raise ValueError("EXPECTED_ONE_PRE_CLOSED_WPE_RUNTIME:" + str(len(matches)))
    base.inventory(matches[0])
    return matches[0]

def recover(download: Path, output: Path) -> dict:
    source = verify_source(download)
    if output.exists() or output.is_symlink() or not output.parent.is_dir() or output.parent.is_symlink():
        raise ValueError("OUTPUT_ALREADY_EXISTS_OR_UNSAFE_PARENT")
    if output.resolve().is_relative_to(download.resolve()) or download.resolve().is_relative_to(output.resolve()):
        raise ValueError("INPUT_OUTPUT_OVERLAP")
    entries = base.manifest_entries(source)
    if not set(REQUIRED[2:]).issubset(entries):
        raise ValueError("MANDATORY_WPE_FILES_NOT_HASHED")
    repaired = []
    with tempfile.TemporaryDirectory(prefix=".fire4nix-preclosure-", dir=output.parent) as scratch:
        copied = Path(scratch) / "runtime"
        shutil.copytree(source, copied)
        for rel, expected in sorted(entries.items()):
            f = copied / rel
            if not f.exists():
                if not rel.startswith("lib/") or ".so." not in f.name:
                    raise ValueError("UNRECOVERABLE_REQUIRED_FILE:" + rel)
                candidates = [
                    p for p in f.parent.iterdir()
                    if p.is_file() and not p.is_symlink()
                    and p.name.startswith(f.name + ".") and base.digest(p) == expected
                ]
                if len(candidates) != 1:
                    raise ValueError("UNPROVEN_WPE_SONAME_ALIAS:" + rel)
                shutil.copyfile(candidates[0], f)
                repaired.append(rel)
            if not f.is_file() or f.is_symlink() or base.digest(f) != expected:
                raise ValueError("WPE_SHA256_VERIFICATION_FAILED:" + rel)
        for rel in REQUIRED:
            f = copied / rel
            if not f.is_file() or f.is_symlink() or f.stat().st_size <= 0:
                raise ValueError("INCOMPLETE_REAL_WPE_STAGE:" + rel)
        report = (copied / "BUILD-REPORT.txt").read_text(encoding="utf-8").splitlines()
        if any(report.count(proof) != 1 for proof in PROOF_LINES):
            raise ValueError("UNVERIFIED_WPE_BUILD_PROFILE")
        if (copied / "libexec/wpe-webkit-2.0/WPEGPUProcess").exists():
            raise ValueError("GPU_OFF_RUNTIME_CONTAINS_GPU_PROCESS")
        os.rename(copied, output)
    return {"path": output.resolve(), "repaired": repaired, "hashed": len(entries)}

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--download-root", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    try:
        result = recover(args.download_root, args.output)
    except (OSError, ValueError, UnicodeError) as exc:
        print("PRE_CLOSED_WPE_RECOVERY=BLOCKED:" + str(exc), file=sys.stderr)
        return 6
    print("PRE_CLOSED_WPE_RECOVERY=PASS_SHA256_ONLY", file=sys.stderr)
    print("HASHED_FILES=" + str(result["hashed"]), file=sys.stderr)
    print("REBUILT_SONAMES=" + str(len(result["repaired"])), file=sys.stderr)
    print(result["path"])
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
