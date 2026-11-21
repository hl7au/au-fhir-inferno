"""Tests for run_inferno.py. Run from the repository root:

    python3 -m unittest discover -s docs/ci/tests
"""

import http.client
import json
import os
import socket
import subprocess
import sys
import tempfile
import unittest
import urllib.error
from pathlib import Path
from unittest import mock

from stub_server import StubServer

HERE = Path(__file__).resolve().parent
SCRIPT = HERE.parent / "run_inferno.py"
sys.path.insert(0, str(HERE.parent))
import run_inferno

TOKEN = "Bearer s3cret-token-value"
SUITE = {
    "id": "demo", "version": "1.0.0",
    "inputs": [{"name": "url"}, {"name": "header_name"}, {"name": "header_value"}],
    "test_groups": [{"id": "g1", "short_id": "1", "title": "Group", "test_groups": [],
                     "tests": [{"id": "t1", "short_id": "1.01", "title": "Read"}]}],
}
RESULTS = [
    {"id": "r1", "test_id": "t1", "result": "pass", "test_run_id": "run1", "test_session_id": "s1",
     "inputs": [{"name": "url", "value": "http://fhir-server:8080/fhir", "type": "text"},
                {"name": "header_value", "value": TOKEN, "type": "text"}],
     "outputs": [{"name": "smart_credentials", "value": '{"access_token": "s3cret-access"}'}],
     "requests": [{"id": "q1", "verb": "get", "url": "http://fhir-server:8080/fhir/Patient/x", "status": 200}]},
    {"id": "r2", "test_group_id": "g1", "result": "pass", "test_run_id": "run1", "test_session_id": "s1",
     "inputs": [{"name": "header_value", "value": TOKEN, "type": "text"}], "outputs": []},
]


def inferno(run_status="done", overrides=None):
    """A handler that answers like Inferno; overrides maps (method, path suffix) to an answer."""
    def handler(method, path, body):
        path = path.removeprefix("/suites/api/")
        for (m, suffix), answer in (overrides or {}).items():
            if m == method and path == suffix:
                return answer
        if method == "GET" and path == "test_suites/demo":
            return 200, SUITE
        if method == "POST" and path == "test_sessions":
            return 200, {"id": "s1"}
        if method == "POST" and path == "test_runs":
            return 200, {"id": "run1", "status": run_status}
        if method == "GET" and path == "test_runs/run1":
            return 200, {"id": "run1", "status": run_status}
        if method == "DELETE" and path == "test_runs/run1":
            return 204, None
        if method == "GET" and path == "test_sessions/s1/results":
            return 200, RESULTS
        return 404, {"error": path}
    return handler


class RunScript(unittest.TestCase):
    def run_script(self, handler, *args):
        server = StubServer(handler)
        self.addCleanup(server.close)
        env = {k: v for k, v in os.environ.items() if k != "GITHUB_STEP_SUMMARY"}
        return subprocess.run([sys.executable, str(SCRIPT), "--inferno", f"{server.url}/suites",
                               "--suite", "demo", *args],
                              check=False, capture_output=True, text=True, timeout=60, env=env)

    def test_output_has_no_input_or_output_values(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "results.json"
            done = self.run_script(inferno(), "--input", "url=http://fhir-server:8080/fhir",
                                   "--input", "header_name=Authorization", "--input", f"header_value={TOKEN}",
                                   "--output", str(out))
            self.assertEqual(done.returncode, 0, done.stderr)
            written = out.read_text(encoding="utf-8")
        self.assertNotIn("s3cret", written)
        self.assertNotIn("s3cret", done.stdout + done.stderr)
        results = json.loads(written)
        self.assertEqual([r["id"] for r in results], ["r1", "r2"])
        self.assertTrue(all("inputs" not in r and "outputs" not in r for r in results))
        self.assertEqual(results[0]["requests"], RESULTS[0]["requests"])
        self.assertEqual(results[0]["result"], "pass")

    def test_timeout_cancels_and_exits_2(self):
        # Inferno answers the cancel with 204 and no body.
        done = self.run_script(inferno(run_status="running"), "--timeout", "0")
        self.assertEqual(done.returncode, 2, done.stderr)
        self.assertIn("did not finish within 0s", done.stderr)
        self.assertNotIn("Traceback", done.stderr)

    def test_answer_that_is_not_json_exits_2(self):
        done = self.run_script(inferno(overrides={("POST", "test_sessions"): (200, "<html>busy</html>")}))
        self.assertEqual(done.returncode, 2, done.stderr)
        self.assertIn("not JSON", done.stderr)
        self.assertNotIn("Traceback", done.stderr)

    def test_dropped_connection_exits_2(self):
        done = self.run_script(inferno(overrides={("POST", "test_runs"): (None, None)}))
        self.assertEqual(done.returncode, 2, done.stderr)
        self.assertIn("no answer from Inferno", done.stderr)
        self.assertNotIn("Traceback", done.stderr)

    def test_http_error_exits_2(self):
        done = self.run_script(inferno(overrides={("POST", "test_runs"): (422, {"errors": "missing"})}))
        self.assertEqual(done.returncode, 2, done.stderr)
        self.assertIn("HTTP 422", done.stderr)

    def test_malformed_input_exits_2_without_its_value(self):
        done = self.run_script(inferno(), "--input", "url=http://x", "--input", "s3cret-without-a-name")
        self.assertEqual(done.returncode, 2, done.stderr)
        self.assertIn("--input number 2 is not NAME=VALUE", done.stderr)
        self.assertNotIn("s3cret", done.stdout + done.stderr)

    def test_unexpected_error_exits_2(self):
        # A session without an id: a KeyError, which must not exit 1 (the regression code).
        done = self.run_script(inferno(overrides={("POST", "test_sessions"): (200, {})}))
        self.assertEqual(done.returncode, 2, done.stderr)
        self.assertIn("KeyError", done.stderr)


class Api(unittest.TestCase):
    def test_empty_body_is_an_empty_dict(self):
        server = StubServer(lambda method, path, body: (204, None))
        self.addCleanup(server.close)
        self.assertEqual(run_inferno.api(server.url, "DELETE", "test_runs/run1"), {})

    def test_network_errors_exit_2(self):
        errors = [urllib.error.URLError("connection refused"), TimeoutError("timed out"),
                  # Not TimeoutError on Python 3.9, which the scripts support.
                  socket.timeout("timed out"),  # noqa: UP041
                  ConnectionResetError("reset"),
                  http.client.RemoteDisconnected("closed"), http.client.IncompleteRead(b"")]
        for error in errors:
            with self.subTest(error=type(error).__name__), \
                    mock.patch("urllib.request.urlopen", side_effect=error), \
                    mock.patch("sys.stderr"):
                with self.assertRaises(SystemExit) as raised:
                    run_inferno.api("http://inferno.invalid", "GET", "test_runs/run1")
                self.assertEqual(raised.exception.code, 2)


class WithoutIo(unittest.TestCase):
    def test_drops_inputs_and_outputs_only(self):
        cleaned = run_inferno.without_io(RESULTS)
        self.assertNotIn("s3cret", json.dumps(cleaned))
        self.assertEqual(cleaned[1], {k: v for k, v in RESULTS[1].items() if k not in ("inputs", "outputs")})
        self.assertIn("inputs", RESULTS[0])  # the original is left alone


if __name__ == "__main__":
    unittest.main()
