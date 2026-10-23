#!/usr/bin/env python3
"""Check that a complete WPE 2.54.1 build is consistent across main scripts.

These are source-contract tests only. They do not build or execute WebKit.
The isolated fourcc patch test exercises actual patch behavior separately.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
PREP = (ROOT / "scripts/prepare-unified-rocknix-wpe2541.sh").read_text()
BUILD = (ROOT / "scripts/build-wpe2541-subprocesses-rocknix.sh").read_text()
FLOW = (ROOT / ".github/workflows/r36h-wpe2541-processes-real-rk3326.yml").read_text()
BUNDLE = (ROOT / "scripts/bundle-rocknix-wpe-sdk-deps.py").read_text()


class IntegratedWPEGCC15LinkTests(unittest.TestCase):
    def test_gcc15_no_outline_in_c_and_cpp(self):
        for lang in ("C", "CXX"):
            self.assertIn(
                'string(APPEND CMAKE_' + lang +
                '_FLAGS_INIT " -I$stage/usr/include -mno-outline-atomics")',
                PREP)
        self.assertIn(
            "WPE_ROCKNIX_GCC15_ATOMICS=NO_OUTLINE_VERIFIED_CMAKE_CACHE", PREP)
        self.assertIn('for language in C CXX; do', PREP)
        self.assertIn("-mno-outline-atomics", PREP)

    def test_guarded_source_patch_before_cmake(self):
        first = PREP.index('python3 "$base/fire4nix/scripts/patch-wpe2541-drm-fourcc.py"')
        configure = PREP.index('cmake -S "$work/source"')
        self.assertLess(first, configure)
        self.assertIn("--source-root", PREP)
        self.assertIn("--report", PREP)
        self.assertIn(
            "WPE_SOURCE_PATCH=WPE2541_WPE_SNAPSHOT_FOURCC_NO_LIBDRM_V1", PREP)
        self.assertTrue((ROOT / "scripts/patch-wpe2541-drm-fourcc.py").is_file())

    def test_libatomic16_and_ccache_are_preserved(self):
        self.assertIn(
            "WPE_ROCKNIX_LIBATOMIC16=PASS_PINNED_GCC_TARGET_LIB64", PREP)
        self.assertIn('-Wl,-rpath-link,$atomic_dir', PREP)
        self.assertIn('CMAKE_MODULE_LINKER_FLAGS_INIT', PREP)
        self.assertIn('WPE_CCACHE_PROFILE=ROCKNIX_TARGET_GCC_OPT_IN', PREP)
        self.assertIn('CMAKE_CXX_COMPILER_LAUNCHER', PREP)
        self.assertIn('--target-toolchain "$sdk"', BUILD)
        self.assertIn('audited_toolchain_libatomic', BUNDLE)

    def test_build_has_exactly_one_real_pass_and_no_executable_report(self):
        self.assertEqual(BUILD.count("WPE_SUBPROCESS_BUILD=PASS_REAL_AARCH64"), 1)
        self.assertEqual(
            BUILD.count("WPE_PRIVATE_RUNTIME_CLOSURE=PASS_SDK_STATIC_SONAMES_NOT_DEVICE_ABI"), 1)
        self.assertEqual(
            BUILD.count('cat "$result" >> "$GITHUB_STEP_SUMMARY"'), 1)
        self.assertEqual(
            BUILD.count('echo \'WPE_PRIVATE_RUNTIME_SDK_DEPENDENCIES=BUNDLED_AND_STATIC_AUDITED\''), 1)
        self.assertNotIn('"$closed_runtime/SDK-BUNDLE-REPORT.txt" >/dev/null', BUILD)
        self.assertEqual(
            BUILD.count('python3 "$repo_root/scripts/audit-wpe-runtime-closure.py"'), 1)

    def test_dispatch_build_enforces_all_gate_markers(self):
        for marker in (
            "WPE_ROCKNIX_GCC15_ATOMICS=NO_OUTLINE_VERIFIED_CMAKE_CACHE",
            "WPE_SOURCE_PATCH=WPE2541_WPE_SNAPSHOT_FOURCC_NO_LIBDRM_V1",
            "WPE_CCACHE_CMAKE_CACHE=PASS_C_AND_CXX_TARGET_COMPILATION",
            "WPE_WAYLAND_PROTOCOLS=ROCKNIX_1_44_DATA_ONLY",
        ):
            self.assertIn(marker, FLOW)
        self.assertIn('actions/cache/save@v4', FLOW)
        self.assertIn('actions/cache/restore@v4', FLOW)


if __name__ == "__main__":
    unittest.main(verbosity=2)
