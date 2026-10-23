#!/usr/bin/env python3
"""Host-only regressions for the single pinned WPE 2.54.1 source correction."""
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/patch-wpe2541-drm-fourcc.py"
REL = Path("Source/WebKit/UIProcess/wpe/AcceleratedBackingStore.cpp")
BEFORE = """/* Copyright (C) 2023 Igalia S.L. */
#include "config.h"
#if OS(ANDROID)
#include <drm/drm_fourcc.h>
#elif USE(LIBDRM)
#include <drm_fourcc.h>
#endif
static Expected<int, String> snapshot() {
    if (wpe_buffer_dma_buf_get_format(dmaBuffer) == DRM_FORMAT_XRGB8888)
        return kOpaque_SkAlphaType;
    return kPremul_SkAlphaType;
}
"""
AFTER = BEFORE.replace(
    "wpe_buffer_dma_buf_get_format(dmaBuffer) == DRM_FORMAT_XRGB8888",
    "wpe_buffer_dma_buf_get_format(dmaBuffer) == 0x34325258u /* DRM_FORMAT_XRGB8888 */",
)


def run(source: Path, report: Path, success: bool) -> subprocess.CompletedProcess[str]:
    proc = subprocess.run(
        [sys.executable, str(SCRIPT), "--source-root", str(source), "--report", str(report)],
        capture_output=True,
        text=True,
        check=False,
    )
    if success:
        assert proc.returncode == 0, (proc.returncode, proc.stderr)
    else:
        assert proc.returncode == 6, (proc.returncode, proc.stdout, proc.stderr)
    return proc


with tempfile.TemporaryDirectory(prefix="fire4nix-fourcc-") as temp:
    root = Path(temp)
    source = root / "source"
    target = source / REL
    target.parent.mkdir(parents=True)
    report = root / "fourcc-patch.txt"
    target.write_text(BEFORE)
    run(source, report, True)
    assert target.read_text() == AFTER
    assert "WPE_SOURCE_PATCH_SCOPE=PRIVATE_EXTRACTED_COPY_ONLY" in report.read_text()
    assert "WPE_SOURCE_PATCH_DRM_GBM_ENABLED=no" in report.read_text()
    run(source, report, False)  # reject double patching
    assert target.read_text() == AFTER
    target.write_text(BEFORE.replace("DRM_FORMAT_XRGB8888", "SOMETHING_ELSE"))
    run(source, report, False)  # reject drifted upstream
    target.write_text(BEFORE.replace("#elif USE(LIBDRM)", "#elif USE(GBM)"))
    run(source, report, False)  # reject altered includes
    target.write_text(BEFORE)
    target.unlink()
    outside = root / "outside.cpp"
    outside.write_text(BEFORE)
    target.symlink_to(outside)
    run(source, report, False)  # no links outside source tree
    assert outside.read_text() == BEFORE
print("WPE2541_FOURCC_PRIVATE_SOURCE_PATCH=PASS_HOST_TESTS_NO_TARGET_EXECUTION")
