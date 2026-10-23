#!/usr/bin/env python3
"""Fail-closed workflow contract for resumable ROCKNIX WPE 2.54.1 builds."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/r36h-wpe2541-processes-real-rk3326.yml"
CONFIGURE = ROOT / "scripts/prepare-unified-rocknix-wpe2541.sh"


class RealWpeCacheContract(unittest.TestCase):
    def setUp(self):
        self.yaml = WORKFLOW.read_text("utf-8")
        self.script = CONFIGURE.read_text("utf-8")

    def test_manual_opt_in_remains(self):
        self.assertIn("on:\n  workflow_dispatch:\n", self.yaml)
        self.assertNotIn("  workflow_run:", self.yaml)
        self.assertNotIn("  schedule:", self.yaml)

    def test_cache_bound_to_explicit_target_compiler_profile(self):
        self.assertIn("FIRE4NIX_WPE_CCACHE: '1'", self.yaml)
        self.assertIn("CCACHE_COMPILERCHECK: content", self.yaml)
        self.assertIn("CCACHE_MAXSIZE: 768M", self.yaml)
        self.assertIn("CCACHE_BASEDIR: ${{ github.workspace }}", self.yaml)
        self.assertIn("ccache --show-stats", self.yaml)
        self.assertEqual(self.yaml.count("wpe2541-rk3326-gcc15-nooutline-source-"), 3)
        self.assertIn("hashFiles('fire4nix/scripts/prepare-unified-rocknix-wpe2541.sh')", self.yaml)
        self.assertIn("github.run_id", self.yaml)

    def test_cache_restored_before_compilation_and_saved_after_failure(self):
        restore = self.yaml.index("actions/cache/restore@v4")
        configure = self.yaml.index("Configure authentic WPE 2.54.1 reduced Wayland engine")
        build = self.yaml.index("Build native ROCKNIX WPEWebProcess")
        save = self.yaml.index("actions/cache/save@v4")
        self.assertLess(restore, configure)
        self.assertLess(configure, build)
        self.assertLess(build, save)
        self.assertIn("Save bounded GCC15 cache after success or link failure\n        if: always()", self.yaml)
        self.assertIn("continue-on-error: true", self.yaml)

    def test_strict_prebuild_gates_cover_gcc15_and_fourcc(self):
        self.assertIn("WPE_CCACHE_CMAKE_CACHE=PASS_C_AND_CXX_TARGET_COMPILATION", self.yaml)
        self.assertIn("WPE_ROCKNIX_GCC15_ATOMICS=NO_OUTLINE_VERIFIED_CMAKE_CACHE", self.yaml)
        self.assertIn("WPE_SOURCE_PATCH=WPE2541_WPE_SNAPSHOT_FOURCC_NO_LIBDRM_V1", self.yaml)
        self.assertIn("FIRE4NIX_WPE_CCACHE:-0", self.script)
        self.assertIn("CMAKE_C_COMPILER_LAUNCHER:STRING=", self.script)
        self.assertIn("CMAKE_CXX_COMPILER_LAUNCHER:STRING=", self.script)

    def test_cache_does_not_save_or_overwrite_device_runtime(self):
        self.assertIn("path: ${{ env.CCACHE_DIR }}", self.yaml)
        self.assertNotIn("actions/cache/save@v4\n        with:\n          path: wpe-unified-sdk-build/private-", self.yaml)
        self.assertIn("R36H_INSTALLABLE=no", (ROOT / "scripts/build-wpe2541-subprocesses-rocknix.sh").read_text())


if __name__ == "__main__":
    unittest.main(verbosity=2)
