#!/usr/bin/env python3
"""Host-side profile gates for the unified WPE 2.54.1 ROCKNIX build.

The complete target compiler, original WPE source and stage1 SDK are
verified in other jobs; this is a static contract, never a browser test.
"""
from pathlib import Path
import re
import unittest

ROOT=Path(__file__).resolve().parents[2]
CONFIG=ROOT/"scripts/prepare-unified-rocknix-wpe2541.sh"
BUILD=ROOT/"scripts/build-wpe2541-subprocesses-rocknix.sh"
RUNTIME=ROOT/"scripts/bundle-rocknix-wpe-sdk-deps.py"
WF=ROOT/".github/workflows/r36h-wpe2541-processes-real-rk3326.yml"
PATCH=ROOT/"scripts/patch-wpe2541-drm-fourcc.py"

class WPEUnifiedProfileContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cfg=CONFIG.read_text()
        cls.build=BUILD.read_text()
        cls.bundler=RUNTIME.read_text()
        cls.workflow=WF.read_text()

    def test_single_immutable_wpe_source_with_private_patch(self):
        self.assertIn("wpewebkit-2.54.1.tar.xz",self.cfg)
        self.assertIn("0de8bdfba011f9cd63ba9a9171fa6038dd2c08237894f4082abbb821f29d3fe9",self.cfg)
        self.assertIn('scripts/patch-wpe2541-drm-fourcc.py',self.cfg)
        self.assertIn("WPE2541_WPE_SNAPSHOT_FOURCC_NO_LIBDRM_V1",self.cfg)
        self.assertLess(self.cfg.index('sha256sum --check'),self.cfg.index('patch-wpe2541-drm-fourcc.py'))
        self.assertTrue(PATCH.is_file())

    def test_all_c_and_cxx_compile_objects_use_inline_aarch64_atomics(self):
        self.assertRegex(self.cfg,r'CMAKE_C_FLAGS_INIT .*?-mno-outline-atomics')
        self.assertRegex(self.cfg,r'CMAKE_CXX_FLAGS_INIT .*?-mno-outline-atomics')
        self.assertIn("WPE_ROCKNIX_GCC15_ATOMICS=NO_OUTLINE_VERIFIED_CMAKE_CACHE",self.cfg)
        self.assertIn('for language in C CXX',self.cfg)

    def test_16_byte_atomics_are_from_same_rocknix_toolchain(self):
        self.assertIn('-print-file-name=libatomic.so.1',self.cfg)
        self.assertIn('aarch64-rocknix-linux-gnu/lib64',self.cfg)
        self.assertIn('WPE_ROCKNIX_LIBATOMIC16=PASS_PINNED_GCC_TARGET_LIB64',self.cfg)
        for var in ('CMAKE_EXE_LINKER_FLAGS_INIT','CMAKE_SHARED_LINKER_FLAGS_INIT',
                    'CMAKE_MODULE_LINKER_FLAGS_INIT'):
            self.assertIn(var,self.cfg)
        self.assertGreaterEqual(self.cfg.count("-Wl,-rpath-link,$atomic_dir"),3)
        self.assertIn('--target-toolchain "$sdk"',self.build)
        self.assertIn('WPE_TARGET_LIBATOMIC16_BUNDLED=',self.build)
        self.assertIn('audited_toolchain_libatomic',self.bundler)
        self.assertIn('WPE_TARGET_LIBATOMIC16_BUNDLED=',self.bundler)
        self.assertNotIn('--allow-shlib-undefined',self.cfg)

    def test_cache_and_wayland_profile_remain_fail_closed(self):
        self.assertIn('FIRE4NIX_WPE_CCACHE',self.cfg)
        self.assertIn('WPE_CCACHE_CMAKE_CACHE=PASS_C_AND_CXX_TARGET_COMPILATION',self.cfg)
        self.assertIn('USE_GSTREAMER=OFF',self.cfg)
        self.assertIn('USE_GBM=OFF',self.cfg)
        self.assertIn('USE_LIBDRM=OFF',self.cfg)
        self.assertIn('WPE_WAYLAND_PROTOCOLS=ROCKNIX_1_44_DATA_ONLY',self.cfg)
        self.assertIn("workflow_dispatch:",self.workflow)
        self.assertIn("WPE_ROCKNIX_GCC15_ATOMICS=NO_OUTLINE_VERIFIED_CMAKE_CACHE",self.workflow)
        self.assertIn("WPE_SOURCE_PATCH=WPE2541_WPE_SNAPSHOT_FOURCC_NO_LIBDRM_V1",self.workflow)
        self.assertIn("CCACHE_MAXSIZE: 768M",self.workflow)

if __name__=="__main__":
    unittest.main(verbosity=2)
