"""A stand-in Worker for testing templates/cf-worker-app/scripts/smoke.sh.

Serves the three things the smoke script asserts, and can serve each of them wrongly on
request, so the tests can prove the script FAILS when the deployment is broken. A smoke
check that only ever passes is worse than none: it reports health it never measured.

    python3 smoke-fixture-server.py <mode> <port-file>

Modes: good | missing-header | expired-security-txt | bad-healthz | no-security-txt
"""

import http.server
import json
import sys
import threading
from datetime import datetime, timedelta, timezone

MODE = sys.argv[1] if len(sys.argv) > 1 else "good"
PORT_FILE = sys.argv[2] if len(sys.argv) > 2 else "port.txt"

SECURITY_HEADERS = {
    "Strict-Transport-Security": "max-age=31536000; includeSubDomains",
    "Content-Security-Policy": "default-src 'self'; frame-ancestors 'none'",
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "strict-origin-when-cross-origin",
    "X-Frame-Options": "DENY",
}


def security_txt() -> str:
    offset = timedelta(days=-1) if MODE == "expired-security-txt" else timedelta(days=365)
    expires = (datetime.now(timezone.utc) + offset).strftime("%Y-%m-%dT%H:%M:%S.000Z")
    return f"Contact: https://example.test/report\nExpires: {expires}\nPreferred-Languages: en\n"


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args: object) -> None:  # noqa: D102 - keep the test output clean
        pass

    def _send(self, status: int, body: str, content_type: str) -> None:
        payload = body.encode()
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        for name, value in SECURITY_HEADERS.items():
            if MODE == "missing-header" and name == "X-Frame-Options":
                continue
            self.send_header(name, value)
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self) -> None:  # noqa: N802 - name fixed by BaseHTTPRequestHandler
        if self.path == "/healthz":
            if MODE == "bad-healthz":
                self._send(500, "boom", "text/plain")
            else:
                self._send(200, json.dumps({"version": "v1.2.3"}), "application/json")
        elif self.path == "/.well-known/security.txt":
            if MODE == "no-security-txt":
                self._send(404, "not found", "text/plain")
            else:
                self._send(200, security_txt(), "text/plain; charset=utf-8")
        else:
            self._send(200, "Hello from fixture", "text/plain")


server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
with open(PORT_FILE, "w", encoding="utf-8") as handle:
    handle.write(str(server.server_address[1]))
threading.Thread(target=server.serve_forever, daemon=True).start()
# Serve until the parent kills us; the tests do that after each case.
threading.Event().wait()
