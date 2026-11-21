"""A tiny HTTP server for the tests: each test says how to answer each request."""

import http.server
import json
import threading


class StubServer:
    """Serve on a free local port. handler(method, path, body) returns (status, body).

    body is a dict or list (sent as JSON), a str or bytes (sent as is), or None (no body).
    Returning the status None closes the connection without an answer.
    """

    def __init__(self, handler):
        self.requests = []
        outer = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def answer(self):
                length = int(self.headers.get("Content-Length") or 0)
                raw = self.rfile.read(length) if length else b""
                body = json.loads(raw) if raw else None
                outer.requests.append((self.command, self.path, body))
                status, payload = handler(self.command, self.path, body)
                if status is None:
                    self.close_connection = True
                    self.wfile.flush()
                    self.connection.shutdown(2)
                    return
                if isinstance(payload, (dict, list)):
                    payload = json.dumps(payload)
                data = payload.encode("utf-8") if isinstance(payload, str) else payload or b""
                self.send_response(status)
                if data:
                    self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            do_GET = do_POST = do_PUT = do_DELETE = answer

            def log_message(self, *args):
                pass

        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.url = f"http://127.0.0.1:{self.server.server_address[1]}"
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def close(self):
        self.server.shutdown()
        self.server.server_close()
