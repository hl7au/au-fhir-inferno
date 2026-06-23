#!/usr/bin/env python3
"""
Validator warmer / synthetic health check.

Runs one au_ps_bundle validation through Inferno's real API path
(Inferno -> worker -> validator -> tx server). Serves two purposes:

  1. WARM-UP: keeps the validator's session engine and terminology cache hot, and
     re-warms them after a validator pod restart. Because it goes through Inferno it
     warms the *same* validator session id real users hit (a self-prewarm on the
     validator would use a throwaway id and not help Inferno's path).
  2. SYNTHETIC HEALTH CHECK: exercises the full validation chain end to end on a
     schedule. Exits non-zero on an infrastructure failure (unreachable, run errored,
     timeout) so the CronJob surfaces it; benign validation warnings/errors in the
     bundle do NOT fail the check (those are data-dependent and expected).

Stdlib only. Config via env: INFERNO_URL, TEST_SUITE_ID, PROFILE, BUNDLE_PATH, POLL_TIMEOUT.
"""
import json, os, sys, time, urllib.request, urllib.error

URL = os.environ.get("INFERNO_URL", "http://inferno:4567").rstrip("/")
SUITE = os.environ.get("TEST_SUITE_ID", "suite_100preview")
PROFILE = os.environ.get("PROFILE", "http://hl7.org.au/fhir/ps/StructureDefinition/au-ps-bundle")
BUNDLE_PATH = os.environ.get("BUNDLE_PATH", "/warmer/warmer-bundle.json")
POLL_TIMEOUT = int(os.environ.get("POLL_TIMEOUT", "300"))
API = f"{URL}/suites/api"


def http(method, path, body=None, timeout=60):
    req = urllib.request.Request(API + path, method=method,
                                 data=(body.encode() if body else None),
                                 headers={"Content-Type": "application/json", "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode() or "{}")


def fail(msg):
    print(f"warmer UNHEALTHY: {msg}", flush=True)
    sys.exit(1)


def main():
    t0 = time.time()
    bundle = open(BUNDLE_PATH).read()
    try:
        session = http("POST", f"/test_sessions?test_suite_id={SUITE}",
                       json.dumps({"preset_id": None, "suite_options": []}))["id"]
        run = http("POST", "/test_runs", json.dumps({
            "test_session_id": session, "test_suite_id": SUITE, "inputs": [
                {"name": "validate_against", "value": json.dumps(["au_ps_bundle"]), "type": "text"},
                {"name": "bundle_resource", "value": bundle, "type": "text"},
                {"name": "profile", "value": PROFILE, "type": "text"},
            ]}))["id"]
    except (urllib.error.URLError, KeyError, ValueError) as e:
        fail(f"could not start validation: {e}")

    deadline = time.time() + POLL_TIMEOUT
    status = None
    while time.time() < deadline:
        try:
            status = http("GET", f"/test_runs/{run}").get("status")
        except urllib.error.URLError as e:
            fail(f"polling failed: {e}")
        if status in ("done", "cancelled"):
            break
        time.sleep(2)
    else:
        fail(f"validation did not finish within {POLL_TIMEOUT}s (last status={status})")

    elapsed = time.time() - t0
    results = http("GET", f"/test_runs/{run}/results")
    counts = {}
    for r in results:
        counts[r.get("result", "?")] = counts.get(r.get("result", "?"), 0) + 1
    # "error" results indicate the run could not execute (infra), not data validation failures.
    errored = counts.get("error", 0)
    print(f"warmer OK: suite={SUITE} status={status} elapsed={elapsed:.1f}s results={dict(sorted(counts.items()))}", flush=True)
    if errored:
        fail(f"{errored} test(s) errored (infrastructure)")


if __name__ == "__main__":
    main()
