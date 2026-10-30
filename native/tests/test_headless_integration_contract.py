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
            "jsc_value_to_string",
            "app.jscValueUnref = &g_object_unref",
            "there is no jsc_value_unref() API",
            "offlineEvaluationFinished",
            "offline DOM, JavaScript, click and computed CSS verification passed",
            "checks.push('location=' + location.href)",
            "checks.push('ready_state=' + document.readyState)",
            "checks.push('html_length=' + (document.documentElement ? document.documentElement.outerHTML.length : 0))",
            "body_text=",
            "ready_state=",
            "html_length=",
            "checks.push('title='",
            "checks.push('inline_js='",
            "checks.push('swatches=' + document.querySelectorAll('.swatch').length)",
            "checks.push('background=' + css.backgroundColor)",
            "checks.push('click_count=' + (count ? count.textContent.trim() : 'MISSING'))",
            "title=PASS",
            "inline_javascript=PASS",
            "background=rgb(16, 24, 39)",
            "click_count=Cliques: 1",
            "app->exitCode = 4",
        ):
            self.assertIn(token, source)
        self.assertIn("#include <gio/gio.h>", source)

    def test_native_browser_history_verification_uses_real_navigation_api(self):
        source = SOURCE.read_text()
        for token in (
            "--verify-navigation",
            "navigationEvaluationFinished",
            "startNavigationEvaluation",
            "app->loadUri(app->view, target)",
            "app->goBack(app->view)",
            "app->goForward(app->view)",
            "app->navigationPhase = 4",
            "app->navigationPhase == 4",
            "Fire4Nix Nav Start|START_JS_OK|true",
            "Fire4Nix Nav Target|TARGET_JS_OK|true",
            "[FIRE4NIX-NAV] history_back=PASS",
            "[FIRE4NIX-NAV] history_forward=PASS",
            "[FIRE4NIX-NAV] page_reload=PASS",
            "[FIRE4NIX-NAV] reload_cycles=2",
            "navigationReloads",
            "navigationPhase == 5",
        ):
            self.assertIn(token, source)

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
            "libglib2.0-bin shared-mime-info",
            "openssl",
            "glib-networking",
            "libgiognutls.so",
            "WPE_HEADLESS_TLS_BACKEND=GLIB_NETWORKING_INSTALLED",
            "WPE_HEADLESS_MIME_DATABASE=SHARED_MIME_INFO_PRESENT",
            "run_network_fixture HTTP",
            "run_network_fixture HTTPS",
            "Set-Cookie",
            "cookie-check.html",
            "/set-cookie",
            "WPE_REDIRECT_COOKIE=PASS_302_SET_COOKIE_SESSION",
            "WPE_HTTPS_INVALID_CERT=REJECTED_AS_REQUIRED",
            "18767",
            "fire4nix-untrusted.crt",
            "invalid_tls_rc",
            "nav-start.html",
            "nav-target.html",
            "--verify-navigation",
            "WPE_NAVIGATION=PASS_TWO_PAGES_BACK_FORWARD_TWO_RELOADS",
            "page_reload=PASS",
            "reload_cycles=2",
            "history_back=PASS",
            "history_forward=PASS",
            'echo "WPE_$label=PASS_REAL_WPE_NETWORK_DOM_JS_CSS_CLICK"',
            "subjectAltName=DNS:localhost,IP:127.0.0.1",
            "WEBKIT_EXEC_PATH=",
            "WPENetworkProcess",
            'test "$mime_type" = "text/html"',
            "2.54.2",
            "WPE_PLATFORM=headless",
            "--verify-offline",
            "WPE_DATA_URI=PASS_REAL_ENGINE_DOM_JS_CSS_CLICK",
            "WPE_FILE_URI=PASS_REAL_HTML_JS_CSS_CLICK",
            "data:text/html;base64,",
        ):
            self.assertIn(token, workflow)
        self.assertNotIn("mock_wpewebkit.cpp", workflow)
        self.assertNotIn("R36H", workflow.upper())


if __name__ == "__main__":
    unittest.main(verbosity=2)
