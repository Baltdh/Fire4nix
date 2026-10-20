import importlib.util
import pathlib
import tempfile
import threading
import time
import unittest
import http.client

source = pathlib.Path(__file__).resolve().parents[2] / 'tools/remote/share_report.py'
spec = importlib.util.spec_from_file_location('share_report', source)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class ReportTest(unittest.TestCase):
    def setUp(self):
        self.s, self.password = m.make_server('PRIVATE <script>alert(1)</script>', 60)
        self.worker = threading.Thread(target=self.s.serve_forever, daemon=True)
        self.worker.start()

    def tearDown(self):
        self.s.shutdown()
        self.s.server_close()
        self.worker.join()

    def request(self, method='GET', path='/', body=None, headers=None):
        c = http.client.HTTPConnection('127.0.0.1', self.s.server_port, timeout=3)
        c.request(method, path, body, headers or {})
        r = c.getresponse()
        answer = r.status, dict(r.getheaders()), r.read()
        c.close()
        return answer

    def test_auth_and_no_shell(self):
        self.assertNotIn(b'PRIVATE', self.request()[2])
        headers = {'Host': 'example.test', 'Origin': 'https://example.test'}
        self.assertEqual(self.request('POST', '/login', 'password=wrong', headers)[0], 403)
        ok = self.request('POST', '/login', 'password=' + self.password, headers)
        self.assertEqual(ok[0], 200)
        self.assertIn(b'&lt;script&gt;', ok[2])
        self.assertIn('Secure; HttpOnly; SameSite=Strict', ok[1]['Set-Cookie'])
        cookie = ok[1]['Set-Cookie'].split(';')[0]
        self.assertIn(b'PRIVATE', self.request(headers={'Cookie': cookie})[2])
        for path in ['/api/terminal/input', '/api/shutdown', '/../../etc/passwd', '/report?path=/etc/passwd']:
            self.assertEqual(self.request('POST', path, 'x')[0], 404)
            self.assertEqual(self.request(path=path)[0], 404)
        self.s.deadline = time.monotonic() - 1
        self.assertEqual(self.request(headers={'Cookie': cookie})[0], 410)

    def test_origin_and_lockout(self):
        self.assertEqual(self.request('POST', '/login', 'password=' + self.password)[0], 403)
        headers = {'Host': 'example.test', 'Origin': 'https://example.test'}
        for _ in range(10):
            self.assertEqual(self.request('POST', '/login', 'password=bad', headers)[0], 403)
        self.assertEqual(self.request('POST', '/login', 'password=' + self.password, headers)[0], 429)

    def test_file_constraints(self):
        with tempfile.TemporaryDirectory() as d:
            p = pathlib.Path(d) / 'report'
            p.write_text('ok')
            self.assertEqual(m.read_report(p), 'ok')
            link = pathlib.Path(d) / 'link'
            link.symlink_to(p)
            with self.assertRaises(OSError):
                m.read_report(link)
            p.write_bytes(b'x' * (m.MAX_REPORT + 1))
            with self.assertRaises(ValueError):
                m.read_report(p)
        with self.assertRaises(ValueError):
            m.make_server('', 901)


if __name__ == '__main__':
    unittest.main()
