#!/usr/bin/env python3
"""Temporary loopback report viewer. No shell, upload, proxy or file browsing."""
import argparse
import hmac
import html
import secrets
import signal
import stat
import os
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from http.cookies import SimpleCookie

MAX_REPORT = 2 * 1024 * 1024


def read_report(path):
    fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_size > MAX_REPORT:
            raise ValueError('Report must be a regular file of at most 2 MiB')
        with os.fdopen(fd, 'rb', closefd=False) as stream:
            data = stream.read(MAX_REPORT + 1)
        if len(data) > MAX_REPORT:
            raise ValueError('Report grew beyond 2 MiB')
        return data.decode('utf-8', 'replace')
    finally:
        os.close(fd)


def make_server(report, lifetime, port=0):
    if not 1 <= lifetime <= 900:
        raise ValueError('Lifetime must be 1..900 seconds')
    password = secrets.token_urlsafe(24)
    session = secrets.token_urlsafe(32)
    page = ('<!doctype html><meta charset="utf-8"><title>Fire4Nix relatório</title>'
            '<h1>Relatório somente leitura</h1><pre>' + html.escape(report) + '</pre>').encode()
    login = (b'<!doctype html><meta charset="utf-8"><title>Fire4Nix</title>'
             b'<h1>Fire4Nix</h1><form method="post" action="/login">'
             b'<input type="password" name="password" autocomplete="off" required>'
             b'<button>Consultar relatorio</button></form>')

    class Handler(BaseHTTPRequestHandler):
        server_version = 'Fire4NixReport'
        sys_version = ''

        def setup(self):
            super().setup()
            self.connection.settimeout(2)

        def log_message(self, *args):
            pass  # Never log password, session, URL or report.

        def send(self, status, body, cookie=None):
            self.send_response(status)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Content-Length', str(len(body)))
            self.send_header('Cache-Control', 'no-store')
            self.send_header('Referrer-Policy', 'no-referrer')
            self.send_header('X-Content-Type-Options', 'nosniff')
            self.send_header('Content-Security-Policy', "default-src 'none'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'")
            if cookie:
                self.send_header('Set-Cookie', cookie)
            self.end_headers()
            self.wfile.write(body)

        def expired(self):
            if time.monotonic() >= self.server.deadline:
                self.send(410, b'Expired')
                return True
            return False

        def do_GET(self):
            if self.expired():
                return
            if self.path != '/':
                return self.send(404, b'Not found')
            jar = SimpleCookie()
            try:
                jar.load(self.headers.get('Cookie', ''))
                token = jar.get('__Host-fire4nix')
                authenticated = token and hmac.compare_digest(token.value, session)
            except Exception:
                authenticated = False
            self.send(200, page if authenticated else login)

        def do_POST(self):
            from urllib.parse import parse_qs
            if self.expired():
                return
            if self.path != '/login':
                return self.send(404, b'Not found')
            # HTTPS browser origin only; no reliance on forwarded client IPs.
            if self.headers.get('Origin') != 'https://' + self.headers.get('Host', ''):
                return self.send(403, b'HTTPS origin required')
            if self.headers.get('Transfer-Encoding'):
                return self.send(400, b'Invalid request')
            if self.server.failures >= 10:
                return self.send(429, b'Restart locally to unlock')
            try:
                size = int(self.headers.get('Content-Length', '-1'))
                if not 0 <= size <= 256:
                    raise ValueError()
                body = self.rfile.read(size).decode('ascii')
                supplied = parse_qs(body).get('password', [''])[0]
                valid = hmac.compare_digest(supplied.encode(), password.encode())
            except (ValueError, UnicodeError):
                return self.send(400, b'Invalid request')
            if not valid:
                self.server.failures += 1
                return self.send(403, b'Invalid password')
            self.send(200, page, '__Host-fire4nix=' + session + '; Secure; HttpOnly; SameSite=Strict; Path=/')

    server = HTTPServer(('127.0.0.1', port), Handler)
    server.timeout = 0.25
    server.deadline = time.monotonic() + lifetime
    server.failures = 0
    return server, password


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report', required=True, help='Explicit reviewed text report; never a credential file')
    parser.add_argument('--seconds', type=int, default=600)
    parser.add_argument('--port', type=int, default=8767)
    args = parser.parse_args()
    if not 1 <= args.port <= 65535:
        parser.error('Invalid port')
    # Snapshot only the selected file. It cannot be changed through HTTP.
    server, password = make_server(read_report(args.report), args.seconds, args.port)
    stopped = False

    def stop(*unused):
        nonlocal stopped
        stopped = True

    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)
    print('Somente leitura; nenhum tunel foi aberto.', flush=True)
    print('Origem local: http://127.0.0.1:%d' % server.server_port, flush=True)
    print('Senha temporaria (nao publicar): ' + password, flush=True)
    print('Expira em %d segundos. Ctrl+C encerra.' % args.seconds, flush=True)
    try:
        while not stopped and time.monotonic() < server.deadline:
            server.handle_request()
    finally:
        server.server_close()
        print('Consulta encerrada.', flush=True)


if __name__ == '__main__':
    main()
