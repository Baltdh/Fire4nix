#!/usr/bin/env python3
"""Compile host-only tab regressions and exercise real Make dependency rules."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / 'source_r36h/Fire4Nix'


class TabSelectionTests(unittest.TestCase):
    def test_closing_tabs_preserves_current_identity(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / 'tabs.cpp'
            source.write_text('''
#include "tab_strip.hpp"
#include <cassert>
int main() {
    TabStrip tabs;
    tabs.addTab("A"); tabs.addTab("B"); tabs.addTab("C"); tabs.addTab("D");
    tabs.reset(2);
    tabs.closeTab(0);
    assert(tabs.currentTitle() == "C");
    assert(tabs.currentIndex() == 1);
    tabs.closeTab(2);
    assert(tabs.currentTitle() == "C");
    tabs.closeCurrentTab();
    assert(tabs.currentTitle() == "B");
    tabs.closeCurrentTab();
    assert(tabs.currentTitle() == "Home");
    tabs.closeTab(100);
    assert(tabs.count() == 1);
}
''')
            binary = Path(tmp) / 'tabs'
            subprocess.run(['g++', '-std=c++17', '-Wall', '-Wextra', '-Werror',
                            '-I' + str(APP / 'src/gui'), str(source),
                            str(APP / 'src/gui/tab_strip.cpp'), '-o', str(binary)], check=True)
            subprocess.run([str(binary)], check=True, capture_output=True)


class MakefileTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        shutil.copy2(APP / 'Makefile', self.root / 'Makefile')
        self.pkg = self.root / 'pkg-config'
        self.pkg.write_text('''#!/bin/sh
case "$1" in
 --exists) [ "$2" = wpe-webkit ] ;;
 *) exit 0 ;;
esac
''')
        self.pkg.chmod(0o755)

    def make(self, *args):
        return subprocess.run(['make', '--no-print-directory', 'PKG_CONFIG=' + str(self.pkg),
                               *args], cwd=self.root, text=True, capture_output=True, check=True)

    def test_selects_exactly_one_available_wpe_package(self):
        with (self.root / 'Makefile').open('a') as f:
            f.write('\nprobe-package:\n\t@echo "$(WPE_PKG_NAME)"\n')
        self.assertEqual(self.make('probe-package').stdout.strip(), 'wpe-webkit')

    def test_header_change_rebuilds_dependent_object(self):
        (self.root / 'src').mkdir()
        header = self.root / 'src/value.hpp'
        header.write_text('#define VALUE 1\n')
        (self.root / 'src/main.cpp').write_text('#include "value.hpp"\nint main() { return VALUE; }\n')
        self.make('all')
        self.assertEqual(subprocess.run([str(self.root / 'fire4nix')]).returncode, 1)
        header.write_text('#define VALUE 2\n')
        # No sleeps or filesystem timestamp resolution assumptions.
        self.make('-W', 'src/value.hpp', 'all')
        self.assertEqual(subprocess.run([str(self.root / 'fire4nix')]).returncode, 2)
        (self.root / 'fire4nix-wpe-platform').touch()
        self.make('clean')
        self.assertFalse((self.root / 'src/main.d').exists())
        self.assertFalse((self.root / 'fire4nix-wpe-platform').exists())


if __name__ == '__main__':
    unittest.main()
