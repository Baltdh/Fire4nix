#!/usr/bin/env python3
"""Materialize one genuine downloaded ROCKNIX WPE runtime without guessing SONAMEs.

GitHub Actions zip artifacts do not preserve Unix symlinks reliably. The WPE
stage may contain lib/libWPEWebKit-2.0.so.1 -> libWPEWebKit-2.0.so.1.11.4.
ONLY reconstruct a missing shared ELF alias if the build's own SHA256SUMS.txt
records that exact path and exactly one same-directory versioned regular file
matches the digest. Do not synthesize reports, dependencies or ELF binaries.
Source download is never changed; full ELF/ABI checks run in the packager.
"""
from __future__ import annotations
import argparse
import hashlib
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import sys
import tempfile

LAYOUTS = ("private-wpe-runtime-sdk-closed",
           "wpe-unified-sdk-build/private-wpe-runtime-sdk-closed")
MAX_FILES = 15000
MAX_BYTES = 1600 * 1024 * 1024
REQUIRED = (
    "BUILD-REPORT.txt", "SDK-BUNDLE-REPORT.txt", "SHA256SUMS.txt",
    "lib/libWPEWebKit-2.0.so.1",
    "libexec/wpe-webkit-2.0/WPEWebProcess",
    "libexec/wpe-webkit-2.0/WPENetworkProcess",
    "lib/wpe-webkit-2.0/injected-bundle/libWPEInjectedBundle.so",
    "share/wpe-webkit-2.0/inspector.gresource",
)
SHA_LINE = re.compile(r"([a-f0-9]{64})  (.+)")


def digest(path: Path) -> str:
    with path.open("rb") as f:
        return hashlib.file_digest(f, "sha256").hexdigest()


def locate(download: Path) -> Path:
    if not download.is_dir() or download.is_symlink():
        raise ValueError("INVALID_DOWNLOAD_ROOT")
    found = []
    for rel in LAYOUTS:
        d = download / rel
        if d.exists() or d.is_symlink():
            if not d.is_dir() or d.is_symlink() or any(
                part.is_symlink() for part in [d, *d.parents] if part != download
            ):
                raise ValueError("UNSAFE_DOWNLOADED_RUNTIME_ROOT")
            found.append(d)
    if len(found) != 1:
        raise ValueError("EXPECTED_EXACTLY_ONE_WPE_RUNTIME:" + str(len(found)))
    return found[0]


def inventory(root: Path) -> None:
    total = 0
    entries = 0
    for path in root.rglob("*"):
        entries += 1
        if entries > MAX_FILES:
            raise ValueError("TOO_MANY_RUNTIME_PATHS")
        # GitHub transport must provide regular files only. Do not follow
        # links to host files, even if they appear inside a source artifact.
        if path.is_symlink():
            raise ValueError("SYMLINKED_DOWNLOADED_RUNTIME:" + str(path.relative_to(root)))
        if path.is_dir():
            continue
        if not path.is_file():
            raise ValueError("SPECIAL_DOWNLOADED_RUNTIME_ENTRY")
        total += path.stat().st_size
        if total > MAX_BYTES:
            raise ValueError("DOWNLOADED_RUNTIME_TOO_LARGE")


def manifest_entries(root: Path) -> dict[str, str]:
    manifest = root / "SHA256SUMS.txt"
    if not manifest.is_file() or manifest.is_symlink():
        raise ValueError("MISSING_WPE_SHA256_MANIFEST")
    result = {}
    for raw in manifest.read_text(encoding="utf-8").splitlines():
        match = SHA_LINE.fullmatch(raw)
        if not match:
            raise ValueError("INVALID_RUNTIME_MANIFEST_ROW")
        sha, rel = match.groups()
        path = PurePosixPath(rel)
        if path.is_absolute() or ".." in path.parts or "." in path.parts or rel in result:
            raise ValueError("UNSAFE_OR_DUPLICATE_RUNTIME_HASH_PATH")
        result[rel] = sha
    return result


def materialize(download: Path, output: Path) -> dict:
    source = locate(download)
    if output.exists() or output.is_symlink() or not output.parent.is_dir() or output.parent.is_symlink():
        raise ValueError("REFUSE_TO_OVERWRITE_OR_MISSING_PARENT")
    if output.resolve().is_relative_to(download.resolve()) or download.resolve().is_relative_to(output.resolve()):
        raise ValueError("OUTPUT_AND_DOWNLOAD_OVERLAP")
    inventory(source)
    entries = manifest_entries(source)
    repaired = []
    with tempfile.TemporaryDirectory(prefix=".fire4nix-artifact-copy-", dir=output.parent) as scratch:
        target = Path(scratch) / "private-wpe-runtime-sdk-closed"
        shutil.copytree(source, target)
        for relative, expected in sorted(entries.items()):
            path = target / relative
            if not path.exists():
                # Recovery is never allowed for missing inspector, processes,
                # reports or non-library files.
                if not relative.startswith("lib/") or ".so." not in path.name:
                    raise ValueError("UNRECOVERABLE_MISSING_HASHED_FILE:" + relative)
                candidates = [
                    candidate for candidate in path.parent.iterdir()
                    if candidate.is_file() and not candidate.is_symlink()
                    and candidate.name.startswith(path.name + ".")
                    and digest(candidate) == expected
                ]
                if len(candidates) != 1:
                    raise ValueError("NO_UNIQUE_SHA256_PROVEN_SONAME:" + relative)
                shutil.copyfile(candidates[0], path)
                repaired.append(relative)
            if path.is_symlink() or not path.is_file() or digest(path) != expected:
                raise ValueError("DOWNLOADED_RUNTIME_HASH_MISMATCH:" + relative)
        for rel in REQUIRED:
            if not (target / rel).is_file() or not (target / rel).stat().st_size:
                raise ValueError("INCOMPLETE_WPE_RUNTIME_AFTER_RECOVERY:" + rel)
        # Rename only after the entire SHA256 manifest and required filenames
        # pass. A caller may then use the independent full ELF/ABI packager.
        os.rename(target, output)
    return {"path": str(output.resolve()), "repaired": repaired}


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--download-root", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    args = p.parse_args()
    try:
        report = materialize(args.download_root, args.output)
    except (OSError, ValueError, UnicodeError) as exc:
        print("WPE_ARTIFACT_MATERIALIZATION=BLOCKED:" + str(exc), file=sys.stderr)
        return 6
    print("WPE_ARTIFACT_MATERIALIZATION=PASS_VERIFIED_SHA256_ONLY", file=sys.stderr)
    print("WPE_REPAIRED_SONAME_ALIASES=" + str(len(report["repaired"])), file=sys.stderr)
    print(report["path"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
