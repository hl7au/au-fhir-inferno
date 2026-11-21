"""Tests for load_test_data.py. Run from the repository root:

    python3 -m unittest discover -s docs/ci/tests
"""

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from stub_server import StubServer

HERE = Path(__file__).resolve().parent
SCRIPT = HERE.parent / "load_test_data.py"
sys.path.insert(0, str(HERE.parent))
import load_test_data


class References(unittest.TestCase):
    def refs(self, resource):
        return sorted(load_test_data.references(resource))

    def test_reference_held_in_an_element_named_reference(self):
        consent = {"resourceType": "Consent", "id": "c", "patient": {"reference": "Patient/p"},
                   "provision": {"data": [{"meaning": "related",
                                           "reference": {"reference": "ServiceRequest/order-xray-1"}}]}}
        self.assertEqual(self.refs(consent), ["Patient/p", "ServiceRequest/order-xray-1"])

    def test_contained_resources_count_but_local_references_do_not(self):
        request = {"resourceType": "MedicationRequest", "id": "m",
                   "contained": [{"resourceType": "Medication", "id": "med",
                                  "manufacturer": {"reference": "Organization/maker"}}],
                   "medicationReference": {"reference": "#med"},
                   "subject": {"reference": "Patient/p"}}
        self.assertEqual(self.refs(request), ["Organization/maker", "Patient/p"])

    def test_versioned_and_absolute_references(self):
        resource = {"resourceType": "Observation", "id": "o",
                    "subject": {"reference": "Patient/p/_history/2"},
                    "performer": [{"reference": "https://elsewhere.example/fhir/Practitioner/x"}]}
        self.assertEqual(self.refs(resource), ["Patient/p"])

    def test_bundle_contents_are_left_alone(self):
        bundle = {"resourceType": "Bundle", "id": "b", "type": "document",
                  "entry": [{"resource": {"resourceType": "Composition", "subject": {"reference": "Patient/p"}}}]}
        self.assertEqual(self.refs(bundle), [])


def write_resources(folder, resources):
    for resource in resources:
        path = Path(folder) / f"{resource['resourceType']}-{resource['id']}.json"
        path.write_text(json.dumps(resource), encoding="utf-8")


def run_loader(url, folder):
    return subprocess.run([sys.executable, str(SCRIPT), "--base-url", f"{url}/fhir", "--wait", "5", str(folder)],
                          check=False, capture_output=True, text=True, timeout=60)


class Loading(unittest.TestCase):
    def serve(self, handler):
        server = StubServer(handler)
        self.addCleanup(server.close)
        return server

    def test_cycle_goes_in_one_transaction_with_full_urls(self):
        server = self.serve(lambda method, path, body: (200, {"resourceType": "OperationOutcome"}))
        with tempfile.TemporaryDirectory() as tmp:
            write_resources(tmp, [
                {"resourceType": "Patient", "id": "p", "link": [{"other": {"reference": "RelatedPerson/r"}}]},
                {"resourceType": "RelatedPerson", "id": "r", "patient": {"reference": "Patient/p"}},
                {"resourceType": "Observation", "id": "o", "subject": {"reference": "Patient/p"}},
            ])
            done = run_loader(server.url, tmp)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        writes = [(m, p, b) for m, p, b in server.requests if m != "GET"]
        self.assertEqual([(m, p) for m, p, _ in writes], [("POST", "/fhir"), ("PUT", "/fhir/Observation/o")])
        bundle = writes[0][2]
        self.assertEqual(bundle["type"], "transaction")
        self.assertEqual([(e["fullUrl"], e["request"]) for e in bundle["entry"]], [
            (f"{server.url}/fhir/Patient/p", {"method": "PUT", "url": "Patient/p"}),
            (f"{server.url}/fhir/RelatedPerson/r", {"method": "PUT", "url": "RelatedPerson/r"}),
        ])

    def test_referenced_resource_is_written_first(self):
        server = self.serve(lambda method, path, body: (200, None))
        with tempfile.TemporaryDirectory() as tmp:
            write_resources(tmp, [
                {"resourceType": "Consent", "id": "c",
                 "provision": {"data": [{"meaning": "related", "reference": {"reference": "ServiceRequest/s"}}]}},
                {"resourceType": "ServiceRequest", "id": "s"},
            ])
            done = run_loader(server.url, tmp)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        puts = [p for m, p, _ in server.requests if m == "PUT"]
        self.assertEqual(puts, ["/fhir/ServiceRequest/s", "/fhir/Consent/c"])

    def test_stops_early_when_every_write_is_rejected(self):
        def handler(method, path, body):
            if method == "GET":
                return 200, {"resourceType": "CapabilityStatement"}
            return 405, {"resourceType": "OperationOutcome",
                         "issue": [{"severity": "error", "code": "not-supported", "diagnostics": "no update as create"}]}
        server = self.serve(handler)
        with tempfile.TemporaryDirectory() as tmp:
            write_resources(tmp, [{"resourceType": "Patient", "id": f"p{n}"} for n in range(200)])
            done = run_loader(server.url, tmp)
        self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
        self.assertIn("none succeeded", done.stdout)
        self.assertIn("update as create", done.stdout)
        puts = sum(1 for m, _, _ in server.requests if m == "PUT")
        # The first STOP_AFTER failures, plus what the workers had already started.
        self.assertLess(puts, load_test_data.STOP_AFTER + 10)

    def test_no_early_stop_once_a_write_succeeded(self):
        def handler(method, path, body):
            if method == "GET" or path == "/fhir/Patient/p000":
                return 200, None
            return 400, None
        server = self.serve(handler)
        with tempfile.TemporaryDirectory() as tmp:
            # p000 sorts first and goes in the first batch of writes.
            write_resources(tmp, [{"resourceType": "Patient", "id": f"p{n:03}"} for n in range(60)])
            done = subprocess.run([sys.executable, str(SCRIPT), "--base-url", f"{server.url}/fhir", "--workers", "1",
                                   "--wait", "5", tmp], check=False, capture_output=True, text=True, timeout=60)
        self.assertEqual(done.returncode, 1)
        self.assertIn("1 of 60 resources written", done.stdout)


if __name__ == "__main__":
    unittest.main()
