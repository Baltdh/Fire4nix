#!/usr/bin/env python3
"""Static safety/integrity fixture check, NOT proof of WebKit rendering."""
from html.parser import HTMLParser
from pathlib import Path
import re

f = Path(__file__).resolve().parents[2] / "installer/www/primeiro-teste-r36h.html"
source = f.read_text(encoding="utf-8")

class Parser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.tags = []
        self.ids = set()
        self.external = []
    def handle_starttag(self, tag, attrs):
        self.tags.append(tag)
        d = dict(attrs)
        if "id" in d:
            assert d["id"] not in self.ids, f"Duplicate ID: {d['id']}"
            self.ids.add(d["id"])
        if any(key in d for key in ("src", "href", "formaction")):
            for key in ("src", "href", "formaction"):
                if key in d:
                    self.external.append(d[key])

p = Parser()
p.feed(source)
assert len(source) < 12_000, "offline smoke should stay lightweight"
assert "<meta name=\"viewport\"" in source
assert 'width=device-width' in source
assert "max-width:640px" in source and "min-height:480px" in source
assert all(x in p.tags for x in ["style", "script", "button", "main"])
assert {"js", "frame", "action", "click", "key"}.issubset(p.ids)
assert not p.external, f"Offline page must have no linked assets: {p.external}"
assert not re.search(r'https?://|fetch\s*\(|XMLHttpRequest|navigator\.sendBeacon|localStorage|sessionStorage', source, re.I)
assert "JS_OK" in source and "FRAME_OK" in source and "addEventListener('click'" in source
assert "addEventListener('keydown'" in source
print("PASS: offline 640x480 HTML/CSS/JS click and keyboard fixture has no network or storage calls")
print("note: static fixture, no real browser rendered or tested")
