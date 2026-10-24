import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('r36h_patch', ROOT/'scripts/patch-wpe2541-r36h-platform.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

def fixtures():
    files = {p: m.GUARD+'\n// fixture\n#endif\n' for p in m.GUARDED_FILES}
    files[m.WEB] = m.GUARD+'\n#include <WebCore/PlatformDisplayDefault.h>\n#endif\n'+m.GUARD+'\n    if (auto display = PlatformDisplayDefault::create()) { return; }\n#endif\n'
    files[m.PROCESS] = '#if ENABLE(DEVELOPER_MODE)\n    static const char* execDirectory = g_getenv("WEBKIT_EXEC_PATH");\n    if (execDirectory) { return; }\n    static String executablePath = getExecutablePath();\n#endif\n'
    return files

class PatchTests(unittest.TestCase):
    def test_fallback_is_opt_in_and_release_paths_are_absolute(self):
        result=m.transform(fixtures())
        self.assertIn('g_strcmp0(g_getenv("FIRE4NIX_WPE_DEFAULT_EGL"), "1")',result[m.WEB])
        self.assertIn('execDirectory && g_path_is_absolute(execDirectory)',result[m.PROCESS])
        self.assertLess(result[m.PROCESS].index('g_getenv("WEBKIT_EXEC_PATH")'), result[m.PROCESS].index('#if ENABLE(DEVELOPER_MODE)'))
        for p in m.GUARDED_FILES:
            self.assertIn(m.WPE_GUARD,result[p])

    def test_repeated_patch_is_rejected(self):
        with self.assertRaises(ValueError):
            m.transform(m.transform(fixtures()))

    def test_wrong_anchor_does_not_modify_any_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            files=fixtures();files[m.PROCESS]='unrecognized source'
            for p,s in files.items():
                f=root/p;f.parent.mkdir(parents=True,exist_ok=True);f.write_text(s)
            with self.assertRaises(ValueError):
                m.apply(root,root/'report.json')
            self.assertEqual(files,{p:(root/p).read_text() for p in files})
            self.assertFalse((root/'report.json').exists())

    def test_symlinked_source_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            for p,s in fixtures().items():
                f=root/p;f.parent.mkdir(parents=True,exist_ok=True);f.write_text(s)
            f=root/m.PROCESS;f.unlink();f.symlink_to(root/m.WEB)
            with self.assertRaisesRegex(ValueError,'UNSAFE_SOURCE_FILE'):
                m.apply(root,root/'report.json')

if __name__=='__main__': unittest.main()
