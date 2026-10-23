#!/usr/bin/env python3
"""Apply one audited WPE 2.54.1 fourcc fix to the private build source tree.

The pinned upstream file only includes drm_fourcc.h under USE(LIBDRM), but
its WPE snapshot helper unconditionally uses DRM_FORMAT_XRGB8888. The minimal
ROCKNIX Wayland profile intentionally has USE_LIBDRM=OFF. Linux fourcc XRGB8888
is 0x34325258 ('X','R','2','4') regardless of whether libdrm is installed.

This script never changes the official downloaded archive or device firmware.
"""
from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import sys

RELATIVE = Path("Source/WebKit/UIProcess/wpe/AcceleratedBackingStore.cpp")
OLD = "wpe_buffer_dma_buf_get_format(dmaBuffer) == DRM_FORMAT_XRGB8888"
NEW = "wpe_buffer_dma_buf_get_format(dmaBuffer) == 0x34325258u /* DRM_FORMAT_XRGB8888 */"
EXPECTED_INCLUDE_GUARD = "#elif USE(LIBDRM)\n#include <drm_fourcc.h>\n#endif"
PATCH_ID = "WPE2541_WPE_SNAPSHOT_FOURCC_NO_LIBDRM_V1"


def apply_patch(source_root: Path, report_path: Path) -> None:
    source = source_root / RELATIVE
    if not source.is_file() or source.is_symlink() or source_root.is_symlink():
        raise ValueError("missing/unsafe pinned WPE 2.54.1 source file")
    original = source.read_bytes()
    try:
        text = original.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise ValueError("unexpected non-UTF8 upstream source") from exc
    if "Copyright (C) 2023 Igalia S.L." not in text or EXPECTED_INCLUDE_GUARD not in text:
        raise ValueError("unexpected WPE source revision or libdrm include structure")
    if text.count(OLD) != 1 or NEW in text:
        raise ValueError("upstream WPE fourcc source anchor missing or already modified")
    modified = text.replace(OLD, NEW)
    if modified.count(NEW) != 1:
        raise ValueError("expected exactly one isolated fourcc replacement")
    if not report_path.parent.is_dir() or report_path.is_symlink():
        raise ValueError("unsafe or missing patch report destination")
    source.write_text(modified, encoding="utf-8")
    before = hashlib.sha256(original).hexdigest()
    after = hashlib.sha256(modified.encode("utf-8")).hexdigest()
    report_path.write_text(
        f"WPE_SOURCE_PATCH={PATCH_ID}\n"
        f"WPE_SOURCE_PATCH_FILE={RELATIVE}\n"
        f"WPE_SOURCE_PATCH_SCOPE=PRIVATE_EXTRACTED_COPY_ONLY\n"
        f"WPE_SOURCE_PATCH_REASON=DRM_FORMAT_XRGB8888_UNDECLARED_WITH_USE_LIBDRM_OFF\n"
        f"WPE_SOURCE_PATCH_ORIGINAL_SHA256={before}\n"
        f"WPE_SOURCE_PATCH_MODIFIED_SHA256={after}\n"
        f"WPE_SOURCE_PATCH_DRM_GBM_ENABLED=no\n"
        f"R36H_INSTALLABLE=no\n",
        encoding="utf-8",
    )


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--source-root", type=Path, required=True)
    p.add_argument("--report", type=Path, required=True)
    args = p.parse_args()
    try:
        apply_patch(args.source_root, args.report)
    except (OSError, ValueError) as exc:
        print(f"ERROR: WPE fourcc patch refused: {exc}", file=sys.stderr)
        return 6
    print(f"WPE_SOURCE_PATCH={PATCH_ID}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
