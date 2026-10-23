#!/usr/bin/env python3
"""Host-only guard for the one-branch real WebKit build and exact ZIP producer."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
TRIAL = (ROOT / ".github/workflows/r36h-wpe2541-unified-gcc15-libatomic-real.yml").read_text()
PRODUCER = (ROOT / ".github/workflows/r36h-first-offline-ports-candidate.yml").read_text()
BRANCH = "build/r36h-unified-wpe2541-gcc15-libatomic-real-20261023"
NAME = "Fire4Nix unified WPE2541 ROCKNIX GCC15 libatomic full link"
ARTIFACT = "Fire4Nix-ROCKNIX-WPE2541-UNIFIED-GCC15-LIBATOMIC-REAL-STATIC-STAGE"


class RealWebKitOneBranchContract(unittest.TestCase):
    def test_one_branch_gated_trigger(self):
        self.assertIn("name: " + NAME, TRIAL)
        self.assertIn("branches: ['" + BRANCH + "']", TRIAL)
        self.assertIn("github.ref == 'refs/heads/" + BRANCH + "'", TRIAL)
        self.assertNotIn("  pull_request:", TRIAL)
        self.assertNotIn("    branches: ['main']", TRIAL)

    def test_producer_reauthenticates_identical_name_branch_and_artifact(self):
        for text in (NAME, BRANCH, ARTIFACT):
            self.assertIn(text, TRIAL)
            self.assertIn(text, PRODUCER)
        self.assertIn("data.conclusion !== 'success'", PRODUCER)
        self.assertIn("data.head_repository?.full_name", PRODUCER)
        self.assertIn("data.event === 'push'", PRODUCER)
        self.assertIn("github.event.workflow_run.conclusion == 'success'", PRODUCER)

    def test_real_build_enforces_gcc15_fourcc_and_libatomic(self):
        for text in (
            "WPE_ROCKNIX_GCC15_ATOMICS=NO_OUTLINE_VERIFIED_CMAKE_CACHE",
            "WPE_SOURCE_PATCH=WPE2541_WPE_SNAPSHOT_FOURCC_NO_LIBDRM_V1",
            "WPE_ROCKNIX_LIBATOMIC16=PASS_PINNED_GCC_TARGET_LIB64",
            "WPE_SUBPROCESS_BUILD=PASS_REAL_AARCH64",
            "WPE_WAYLAND_PROTOCOLS=ROCKNIX_1_44_DATA_ONLY",
            "WPE_CCACHE_CMAKE_CACHE=PASS_C_AND_CXX_TARGET_COMPILATION",
            "scripts/build-wpe2541-subprocesses-rocknix.sh --build",
            "actions/cache/restore@v4",
            "actions/cache/save@v4",
            "actions/upload-artifact@v4",
        ):
            self.assertIn(text, TRIAL)
        self.assertIn("native/tests/test_integrated_wpe_gcc15_libatomic_preflight.py", TRIAL)
        self.assertIn("native/tests/test_wpe2541_fourcc_patch.py", TRIAL)

    def test_no_claim_device_is_proven(self):
        self.assertIn("private-wpe-runtime-sdk-closed/", TRIAL)
        self.assertIn("if: always()", TRIAL)
        self.assertNotIn("R36H_INSTALLABLE=yes", TRIAL)


if __name__ == "__main__":
    unittest.main(verbosity=2)
