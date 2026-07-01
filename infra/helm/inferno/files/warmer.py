#!/usr/bin/env python3
"""
Validator warmer / synthetic health check.

Runs one or more checks (selected via the CHECKS env, comma-separated) to keep the
validator warm and to act as an end-to-end synthetic health check. Every check both
WARMS (so real users don't pay a cold start after a validator restart) and PROBES
(exits non-zero on an infrastructure failure so the CronJob surfaces it). Benign,
data-dependent validation warnings/errors never fail the check.

Checks
------
  au_ps              One au_ps_bundle validation through Inferno's real API path
                     (Inferno -> worker -> validator -> tx). Warms the *same* validator
                     session id real AU PS users hit (Inferno keys a session per
                     (test_suite_id, suite_options, validator_name), so going through
                     Inferno is the only way to warm that exact id).

  aucore_wrapper     Direct validator-wrapper /validate for AU Core 1.0.0 and 2.0.0,
                     asserting au-core-patient|<version> resolves. Mints a session then
                     re-sends its id to exercise the reuse/clone path (the path where
                     the historical core 6.6.3 "Unable to resolve profile ...|1.0.0"
                     desync lived). Cheap, no external server needed; warms both base
                     engines + their terminology cache and fails loudly if resolution
                     ever breaks. NOTE: the wrapper mints its own session id and does
                     not persist to Inferno's validator_sessions table, so this warms
                     the validator's engine/tx caches but not Inferno's stored session
                     id -- use aucore_conformance for the same-session, end-to-end warm.

  aucore_conformance A real au_core_v100 / au_core_v200 run through Inferno against a
                     live AU Core server (AUCORE_SERVER_URL). This is the only path that
                     hits the exact (au_core_vXXX, [], :default) session id real users
                     get, and warms the tx cache with real AU Core codes. It depends on
                     an external server, so it is LENIENT: it fails only when the Inferno
                     chain itself is unreachable/errors/times out, never on validation,
                     data, or external-server results.

Stdlib only. Config via env:
  INFERNO_URL, VALIDATOR_URL, TX_SERVER, CHECKS, POLL_TIMEOUT,
  TEST_SUITE_ID, PROFILE, BUNDLE_PATH        (au_ps)
  AUCORE_SERVER_URL                          (aucore_conformance)
"""
import json, os, sys, time, urllib.request, urllib.error

INFERNO_URL = os.environ.get("INFERNO_URL", "http://inferno:4567").rstrip("/")
VALIDATOR_URL = os.environ.get("VALIDATOR_URL", "http://validator-api:3500").rstrip("/")
TX_SERVER = os.environ.get("TX_SERVER", "https://tx.dev.hl7.org.au/fhir")
CHECKS = [c.strip() for c in os.environ.get("CHECKS", "au_ps,aucore_wrapper").split(",") if c.strip()]
POLL_TIMEOUT = int(os.environ.get("POLL_TIMEOUT", "300"))

# au_ps check config
AU_PS_SUITE = os.environ.get("TEST_SUITE_ID", "suite_100preview")
AU_PS_PROFILE = os.environ.get("PROFILE", "http://hl7.org.au/fhir/ps/StructureDefinition/au-ps-bundle")
BUNDLE_PATH = os.environ.get("BUNDLE_PATH", "/warmer/warmer-bundle.json")

# aucore_conformance check config
AUCORE_SERVER_URL = os.environ.get("AUCORE_SERVER_URL", "https://fhir.hl7.org.au/aucore/fhir/DEFAULT")

# AU Core versions to probe / warm. baseEngine keys must match the validator presets
# (validator-presets-configmap.yaml); igs versions must match the suite fhir_resource_validator.
AU_CORE_VERSIONS = [
    {"version": "1.0.0", "ig": "hl7.fhir.au.core#1.0.0", "base_engine": "AU_CORE_V1_0_0", "suite": "au_core_v100"},
    {"version": "2.0.0", "ig": "hl7.fhir.au.core#2.0.0", "base_engine": "AU_CORE_V2_0_0", "suite": "au_core_v200"},
]
AU_CORE_PATIENT = "http://hl7.org.au/fhir/core/StructureDefinition/au-core-patient"


def _http(url, body=None, timeout=60):
    req = urllib.request.Request(
        url, method=("POST" if body is not None else "GET"),
        data=(body.encode() if body else None),
        headers={"Content-Type": "application/json", "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.getcode(), json.loads(r.read().decode() or "{}")


def inferno(method, path, body=None, timeout=60):
    return _http(f"{INFERNO_URL}/suites/api{path}", body if method == "POST" else None, timeout)[1]


class CheckFailure(Exception):
    """An infrastructure failure that should fail the CronJob (non-zero exit)."""


# --------------------------------------------------------------------------- au_ps

def check_au_ps():
    bundle = open(BUNDLE_PATH).read()
    try:
        session = inferno("POST", f"/test_sessions?test_suite_id={AU_PS_SUITE}",
                          json.dumps({"preset_id": None, "suite_options": []}))["id"]
        run = inferno("POST", "/test_runs", json.dumps({
            "test_session_id": session, "test_suite_id": AU_PS_SUITE, "inputs": [
                {"name": "validate_against", "value": json.dumps(["au_ps_bundle"]), "type": "text"},
                {"name": "bundle_resource", "value": bundle, "type": "text"},
                {"name": "profile", "value": AU_PS_PROFILE, "type": "text"},
            ]}))["id"]
    except (urllib.error.URLError, KeyError, ValueError) as e:
        raise CheckFailure(f"au_ps: could not start validation: {e}")

    status = _poll_run(run, f"au_ps[{AU_PS_SUITE}]")
    counts = _result_counts(run)
    # "error" results indicate the run could not execute (infra), not data validation failures.
    if counts.get("error", 0):
        raise CheckFailure(f"au_ps: {counts['error']} test(s) errored (infrastructure)")
    return f"au_ps[{AU_PS_SUITE}] status={status} results={counts}"


# ------------------------------------------------------------------- aucore_wrapper

def _aucore_patient(version):
    return json.dumps({
        "resourceType": "Patient", "id": "warmer",
        "meta": {"profile": [f"{AU_CORE_PATIENT}|{version}"]},
        "name": [{"family": "Warmer", "given": ["Validator"]}], "gender": "male",
    })


def _wrapper_validate(v, session_id=None):
    profile = f"{AU_CORE_PATIENT}|{v['version']}"
    ctx = {
        "sv": "4.0.1", "igs": [v["ig"]], "extensions": ["any"],
        "disableDefaultResourceFetcher": False, "txServer": TX_SERVER,
        "noEcosystem": True, "baseEngine": v["base_engine"], "profiles": [profile],
    }
    body = {"cliContext": ctx,
            "filesToValidate": [{"fileName": "patient.json",
                                 "fileContent": _aucore_patient(v["version"]), "fileType": "json"}]}
    if session_id:
        body["sessionId"] = session_id
    try:
        code, resp = _http(f"{VALIDATOR_URL}/validate", json.dumps(body), timeout=POLL_TIMEOUT)
    except urllib.error.HTTPError as e:
        # A 500 here is exactly the historical failure mode (asSdList throwing an
        # unhandled java.lang.Error). Surface the body.
        raise CheckFailure(f"aucore_wrapper[{v['version']}]: HTTP {e.code}: {e.read().decode()[:300]}")
    except urllib.error.URLError as e:
        raise CheckFailure(f"aucore_wrapper[{v['version']}]: validator unreachable: {e}")
    issues = (resp.get("outcomes") or [{}])[0].get("issues", [])
    unresolved = [i for i in issues if "resolve profile" in i.get("message", "").lower()
                  or i.get("message", "").startswith("Unable to resolve")]
    if unresolved:
        raise CheckFailure(f"aucore_wrapper[{v['version']}]: profile did not resolve: "
                           f"{unresolved[0].get('message')}")
    return resp.get("sessionId"), len(issues)


def check_aucore_wrapper():
    out = []
    for v in AU_CORE_VERSIONS:
        # 1) mint a session (fresh build), 2) re-send its id to exercise the reuse/clone path.
        sid, n1 = _wrapper_validate(v)
        _, n2 = _wrapper_validate(v, session_id=sid) if sid else (None, n1)
        out.append(f"{v['version']}(fresh={n1},reuse={n2})")
    return "aucore_wrapper resolved: " + ", ".join(out)


# --------------------------------------------------------------- aucore_conformance

def check_aucore_conformance():
    # LENIENT: warms the real Inferno session id + tx cache against a live server. Only an
    # unreachable/timed-out Inferno chain fails the check; validation/data/external-server
    # results (including a fully-down reference server) are expected and do not fail.
    out = []
    for v in AU_CORE_VERSIONS:
        suite = v["suite"]
        try:
            session = inferno("POST", f"/test_sessions?test_suite_id={suite}",
                              json.dumps({"preset_id": None, "suite_options": []}))["id"]
            run = inferno("POST", "/test_runs", json.dumps({
                "test_session_id": session, "test_suite_id": suite,
                "inputs": [{"name": "url", "value": AUCORE_SERVER_URL, "type": "text"}]}))["id"]
        except (urllib.error.URLError, KeyError, ValueError) as e:
            raise CheckFailure(f"aucore_conformance[{suite}]: could not start run: {e}")
        status = _poll_run(run, f"aucore_conformance[{suite}]")
        out.append(f"{suite} status={status} results={_result_counts(run)}")
    return "aucore_conformance: " + " | ".join(out)


# --------------------------------------------------------------------------- helpers

def _poll_run(run, label):
    deadline = time.time() + POLL_TIMEOUT
    status = None
    while time.time() < deadline:
        try:
            status = inferno("GET", f"/test_runs/{run}").get("status")
        except urllib.error.URLError as e:
            raise CheckFailure(f"{label}: polling failed: {e}")
        if status in ("done", "cancelled"):
            return status
        time.sleep(2)
    raise CheckFailure(f"{label}: run did not finish within {POLL_TIMEOUT}s (last status={status})")


def _result_counts(run):
    counts = {}
    for r in inferno("GET", f"/test_runs/{run}/results"):
        counts[r.get("result", "?")] = counts.get(r.get("result", "?"), 0) + 1
    return dict(sorted(counts.items()))


CHECK_FUNCS = {
    "au_ps": check_au_ps,
    "aucore_wrapper": check_aucore_wrapper,
    "aucore_conformance": check_aucore_conformance,
}


def main():
    t0 = time.time()
    unknown = [c for c in CHECKS if c not in CHECK_FUNCS]
    if unknown:
        print(f"warmer UNHEALTHY: unknown check(s) {unknown}; valid: {list(CHECK_FUNCS)}", flush=True)
        sys.exit(2)
    failures = []
    for name in CHECKS:
        try:
            print(f"warmer OK: {CHECK_FUNCS[name]()}", flush=True)
        except CheckFailure as e:
            print(f"warmer UNHEALTHY: {e}", flush=True)
            failures.append(name)
    print(f"warmer done: checks={CHECKS} failed={failures} elapsed={time.time() - t0:.1f}s", flush=True)
    if failures:
        sys.exit(1)


if __name__ == "__main__":
    main()
