#!/usr/bin/env python3
"""Static regressions for the first R36H offline page and visual-test launcher."""
from html.parser import HTMLParser
from pathlib import Path
import re
import unittest

BASE = Path(__file__).resolve().parents[2]
TEST_PAGE = BASE / "installer/www/primeiro-teste.html"
HOME = BASE / "installer/www/inicio.html"
VISUAL = BASE / "installer/Fire4Nix-Teste.sh"


class Elements(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.ids = set()
        self.refs = []
        self.scripts = []
        self.in_script = False
        self.titles = []

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if "id" in a:
            self.ids.add(a["id"])
        for attribute in ("src", "href"):
            if attribute in a:
                self.refs.append(a[attribute])
        if tag == "script":
            self.in_script = True
            if "src" in a:
                raise AssertionError("First test must not load external JavaScript")

    def handle_endtag(self, tag):
        if tag == "script":
            self.in_script = False

    def handle_data(self, data):
        if self.in_script:
            self.scripts.append(data)


class FirstOfflineVisualTests(unittest.TestCase):
    def setUp(self):
        self.html = TEST_PAGE.read_text("utf-8")
        self.soup = Elements()
        self.soup.feed(self.html)

    def test_everything_on_page_is_offline(self):
        self.assertGreater(len(self.html), 500)
        self.assertTrue(self.html.startswith("<!doctype html>"))
        self.assertFalse(any(re.match(r"(?i)(?:https?:|//|data:)", path)
                             for path in self.soup.refs))
        self.assertFalse(any(url.startswith("/") for url in self.soup.refs))
        self.assertNotRegex(self.html, r"(?i)<(?:iframe|img|video|audio)\b")
        self.assertIn('<meta name="viewport"', self.html)
        self.assertIn("max-width:640px", self.html)

    def test_three_manual_color_patches_and_script_status(self):
        for required in ("css-state", "js-state", "details", "test-button",
                         "click-count"):
            self.assertIn(required, self.soup.ids)
        self.assertIn("VISÍVEL?", self.html)
        self.assertIn("PENDENTE", self.html)
        self.assertIn("JS OK", self.html)
        self.assertIn("JS FALHOU", self.html)
        self.assertEqual(self.html.count('class="swatch"'), 3)
        self.assertIn("button.addEventListener", self.html)
        self.assertEqual(len(self.soup.scripts), 1)

    def test_home_page_exposes_local_visual_test(self):
        self.assertIn('href="primeiro-teste.html"', HOME.read_text("utf-8"))

    def test_visual_script_uses_first_test_page_for_both_paths(self):
        shell = VISUAL.read_text("utf-8")
        self.assertEqual(shell.count('file://$installed_root/www/primeiro-teste.html'), 2)
        self.assertNotIn('file://$installed_root/www/inicio.html', shell)
        self.assertIn("visual_test_manual_checks=HTML_CSS_THREE_COLORS_AND_JS_OK", shell)
        self.assertIn("PAGE_LOAD_SIGNAL_ONLY_MANUALLY_CONFIRM_CSS_AND_JS", shell)
        self.assertIn("GRAPHICAL_HARDWARE_STATUS=UNVERIFIED_UNTIL_PHYSICAL_TEST", shell)
        self.assertIn("BLOCKED_MISSING_OFFLINE_TEST_PAGE", shell)


if __name__ == "__main__":
    unittest.main(verbosity=2)
