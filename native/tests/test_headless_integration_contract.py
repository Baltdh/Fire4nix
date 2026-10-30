#!/usr/bin/env python3
"""Contracts for real WPEPlatform headless offline browser verification."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "native/fire4nix_wpeplatform.cpp"
PAGE = ROOT / "installer/www/primeiro-teste.html"
WORKFLOW = ROOT / ".github/workflows/wpe-headless-arm64-integration.yml"


class HeadlessIntegrationContract(unittest.TestCase):
    def test_native_verifier_uses_real_webkit_async_javascript_api(self):
        source = SOURCE.read_text()
        for token in (
            "--verify-offline",
            "webkit_web_view_evaluate_javascript",
            "webkit_web_view_evaluate_javascript_finish",
            "jsc_value_to_boolean",
            "offlineEvaluationFinished",
            "offline DOM, JavaScript and computed CSS verification passed",
            "rgb(16, 24, 39)",
            "document.querySelectorAll('.swatch').length === 3",
            "button.click()",
            "count.textContent.trim() === 'Cliques: 1'",
            "app->exitCode = 4",
        ):
            self.assertIn(token, source)
        self.assertIn("#include <gio/gio.h>", source)

    def test_page_is_a_self_contained_offline_fixture(self):
        page = PAGE.read_text()
        for token in (
            "<title>Fire4Nix | Primeiro teste offline</title>",
            'id="js-state"',
            'id="test-button"',
            'class="swatch"',
            "JS OK",
            "document.createElement",
        ):
            self.assertIn(token, page)
        self.assertEqual(page.count('class="swatch"'), 3)
        self.assertNotRegex(page, r'(?i)(?:src|href)\s*=\s*["\']https?://')

    def test_ci_uses_upstream_headless_platform_and_real_engine(self):
        workflow = WORKFLOW.read_text()
        for token in (
            "runs-on: ubuntu-24.04-arm",
            "image: debian:unstable",
            "libwpewebkit-2.0-dev",
            "2.54.2",
            "WPE_PLATFORM=headless",
            "--verify-offline",
            "WPE_HEADLESS_OFFLINE=PASS",
        ):
            self.assertIn(token, workflow)
        self.assertNotIn("mock_wpewebkit.cpp", workflow)
        self.assertNotIn("R36H", workflow.upper())


if __name__ == "__main__":
    unittest.main(verbosity=2)
