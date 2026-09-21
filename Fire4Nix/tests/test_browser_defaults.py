"""Static regression checks; never launches a browser or modifies host audio."""
import ast
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


class BrowserDefaults(unittest.TestCase):
    def test_wrapper_and_profile_keep_security_defaults(self):
        for relative in ("firefox-framebuffer-wrapper.py", ".mozilla_profile/user.js"):
            source = (ROOT / relative).read_text()
            with self.subTest(file=relative):
                self.assertNotRegex(source, r'MOZ_DISABLE_\w+_SANDBOX')
                self.assertNotRegex(source, r'user_pref\("[^"\n]*sandbox[^"\n]*", (?:false|0)\)')
                self.assertNotRegex(source, r'user_pref\("browser\.safebrowsing\.[^"]+", false\)')

    def test_wrapper_syntax_and_no_audio_process_killing(self):
        source = (ROOT / "firefox-framebuffer-wrapper.py").read_text()
        tree = ast.parse(source)
        method = next(node for node in ast.walk(tree)
                      if isinstance(node, ast.FunctionDef) and node.name == "firefox_env")
        environment_setup = ast.get_source_segment(source, method)
        self.assertNotIn('["fuser", "-k"', environment_setup)
        self.assertNotIn('["pulseaudio", "--kill"', environment_setup)

    def test_profile_policy_json(self):
        policy = json.loads((ROOT / ".mozilla_profile/distribution/policies.json").read_text())
        for key in policy["policies"]["Preferences"]:
            self.assertNotIn("sandbox", key)

    def test_chromium_does_not_disable_sandbox(self):
        source = (ROOT / "scripts/fire4nix_env.sh").read_text()
        self.assertNotIn("--no-sandbox", source)
        self.assertNotIn("--disable-gpu-sandbox", source)


if __name__ == "__main__":
    unittest.main()
