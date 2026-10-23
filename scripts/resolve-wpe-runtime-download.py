#!/usr/bin/env python3
"""Resolve the single SDK-closed WPE runtime in a real GitHub Actions download.

actions/upload-artifact flattens the least-common path of its input patterns.
Older artifacts can retain the workspace-name ancestor. Reject ambiguous and
escaping layouts rather than scanning arbitrary folders for impostor runtimes.
"""
from __future__ import annotations
import argparse
from pathlib import Path
import sys

LAYOUTS = (
    "private-wpe-runtime-sdk-closed",
    "wpe-unified-sdk-build/private-wpe-runtime-sdk-closed",
)
REQUIRED = (
    "BUILD-REPORT.txt",
    "SDK-BUNDLE-REPORT.txt",
    "SHA256SUMS.txt",
    "lib/libWPEWebKit-2.0.so.1",
    "libexec/wpe-webkit-2.0/WPEWebProcess",
    "libexec/wpe-webkit-2.0/WPENetworkProcess",
    "lib/wpe-webkit-2.0/injected-bundle/libWPEInjectedBundle.so",
    "share/wpe-webkit-2.0/inspector.gresource",
)


def resolve(download: Path) -> Path:
    if download.is_symlink() or not download.is_dir():
        raise ValueError("INVALID_ARTIFACT_DOWNLOAD_ROOT")
    resolved_root = download.resolve(strict=True)
    candidates = []
    for layout in LAYOUTS:
        path = download / layout
        if not path.exists() and not path.is_symlink():
            continue
        for component in [path, *path.parents]:
            if component == download:
                break
            if component.is_symlink():
                raise ValueError("SYMLINKED_RUNTIME_OR_PARENT")
        if not path.is_dir():
            raise ValueError("INVALID_RUNTIME_PATH")
        resolved = path.resolve(strict=True)
        if not resolved.is_relative_to(resolved_root):
            raise ValueError("RUNTIME_ESCAPES_DOWNLOAD")
        candidates.append(path)
    if len(candidates) != 1:
        raise ValueError("EXPECTED_ONE_SDK_CLOSED_RUNTIME_FOUND_" + str(len(candidates)))
    selected = candidates[0]
    for relative in REQUIRED:
        file = selected / relative
        if not file.is_file() or file.is_symlink() or file.stat().st_size <= 0:
            raise ValueError("MISSING_OR_UNSAFE_WPE_ARTIFACT:" + relative)
    return selected


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--download-root", required=True, type=Path)
    args = parser.parse_args()
    try:
        path = resolve(args.download_root)
    except (OSError, ValueError) as exc:
        print(f"WPE_CLOSED_RUNTIME_DOWNLOAD=BLOCKED:{exc}", file=sys.stderr)
        return 6
    print(path.resolve(strict=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
