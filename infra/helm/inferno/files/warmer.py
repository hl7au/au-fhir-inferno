#!/usr/bin/env python3
"""
Validator session warmer — runs as a SIDECAR in the validator pod.

Purpose: keep the validator's per-session engines pre-built so real users never pay the
cold first-run build (~tens of seconds) after a validator restart. Validator sessions
never time-expire (SESSION_CACHE_DURATION=-1), so warming is only needed *after a
restart* — this sidecar is driven by the validator's lifecycle, not a timer.

Warming goes THROUGH INFERNO. A self-warm on the validator would build a throwaway
session id that Inferno's real runs never reuse, so it would not help. Instead:
  - au_ps: validate a pasted bundle through Inferno (self-contained; no external server).
  - au_core v1.0.0 / v2.0.0: run the capability-statement group through Inferno against a
    live AU Core server. It needs only `url`, and one validation is enough to build+cache
    the suite's real validator session engine.

Trigger model: warm once on startup, then poll the CO-LOCATED validator (localhost). Any
time the validator goes unreachable->reachable it has restarted (covers whole-pod restarts
AND validator-container-only restarts like liveness/OOM), so re-warm.

SAFETY — must never affect the validator's boot or availability:
  * Every operation is wrapped; failures (Inferno down, AU Core server down, a bug) are
    logged and swallowed. The process never exits on error.
  * The container command wraps this with `|| true; sleep infinity` as a final backstop,
    so even an import/syntax error cannot crashloop the container.
  * The sidecar has no probes and never gates the validator container.

Stdlib only. Config via env (all optional):
  INFERNO_URL, VALIDATOR_URL, AUCORE_SERVER_URL, AU_CORE_SUITES,
  AU_PS_SUITE_ID, AU_PS_PROFILE, BUNDLE_PATH, POLL_TIMEOUT, RECHECK_INTERVAL
"""
import json, os, re, time, urllib.request, urllib.error

INFERNO_URL      = os.environ.get("INFERNO_URL", "http://inferno:4567").rstrip("/")
VALIDATOR_URL    = os.environ.get("VALIDATOR_URL", "http://localhost:3500").rstrip("/")
AUCORE_SERVER    = os.environ.get("AUCORE_SERVER_URL", "https://fhir.hl7.org.au/aucore/fhir/DEFAULT")
AU_CORE_SUITES   = [s.strip() for s in os.environ.get("AU_CORE_SUITES", "au_core_v100,au_core_v200").split(",") if s.strip()]
AU_PS_SUITE      = os.environ.get("AU_PS_SUITE_ID", "suite_100preview")
AU_PS_PROFILE    = os.environ.get("AU_PS_PROFILE", "http://hl7.org.au/fhir/ps/StructureDefinition/au-ps-bundle")
AU_PS_BUNDLE     = os.environ.get("BUNDLE_PATH", "/warmer/warmer-bundle.json")
POLL_TIMEOUT     = int(os.environ.get("POLL_TIMEOUT", "300"))
RECHECK_INTERVAL = int(os.environ.get("RECHECK_INTERVAL", "30"))
API = INFERNO_URL + "/suites/api"


def log(msg):
    print(f"[warmer] {msg}", flush=True)


def _http(url, body=None, timeout=30):
    req = urllib.request.Request(
        url, method=("POST" if body is not None else "GET"),
        data=(body.encode() if body else None),
        headers={"Content-Type": "application/json", "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.getcode(), r.read().decode()


def _first_id(raw):
    m = re.search(r'"id"\s*:\s*"([^"]+)"', raw or "")
    return m.group(1) if m else None


def inferno(method, path, body=None, timeout=60):
    return _http(API + path, body if method == "POST" else None, timeout)[1]


def validator_ready():
    try:
        return _http(f"{VALIDATOR_URL}/", timeout=5)[0] == 200
    except Exception:
        return False


def inferno_ready():
    try:
        return _http(f"{API}/test_suites", timeout=5)[0] == 200
    except Exception:
        return False


def wait_until(fn, what, tries=180, delay=5):
    for _ in range(tries):
        if fn():
            return True
        time.sleep(delay)
    log(f"gave up waiting for {what} to be ready")
    return False


def _poll_run(run, label):
    deadline = time.time() + POLL_TIMEOUT
    status = None
    while time.time() < deadline:
        try:
            status = json.loads(inferno("GET", f"/test_runs/{run}") or "{}").get("status")
        except Exception as e:
            log(f"{label}: polling error ({e})")
            return None
        if status in ("done", "cancelled"):
            return status
        time.sleep(3)
    return status


def warm_au_ps():
    try:
        bundle = open(AU_PS_BUNDLE).read()
        session = _first_id(inferno("POST", f"/test_sessions?test_suite_id={AU_PS_SUITE}",
                                    json.dumps({"preset_id": None, "suite_options": []})))
        run = _first_id(inferno("POST", "/test_runs", json.dumps({
            "test_session_id": session, "test_suite_id": AU_PS_SUITE, "inputs": [
                {"name": "validate_against", "value": json.dumps(["au_ps_bundle"]), "type": "text"},
                {"name": "bundle_resource", "value": bundle, "type": "text"},
                {"name": "profile", "value": AU_PS_PROFILE, "type": "text"}]})))
        log(f"au_ps ({AU_PS_SUITE}) warmed: status={_poll_run(run, 'au_ps')}")
    except Exception as e:
        log(f"au_ps warm failed (non-fatal): {e}")


def _capability_group_id(suite):
    info = json.loads(inferno("GET", f"/test_suites/{suite}") or "{}")

    def walk(group):
        for g in group.get("test_groups", []):
            if "capability_statement" in g.get("id", ""):
                return g["id"]
            found = walk(g)
            if found:
                return found
        return None

    return walk(info)


def warm_au_core(suite):
    # Run only the capability-statement group: it needs just `url`, and one validation
    # builds+caches the suite's validator session engine. Lenient — a failure to reach the
    # AU Core server just means this cycle didn't warm; it never errors the sidecar.
    try:
        gid = _capability_group_id(suite)
        if not gid:
            log(f"{suite}: no capability_statement group found; skipping")
            return
        session = _first_id(inferno("POST", f"/test_sessions?test_suite_id={suite}",
                                    json.dumps({"preset_id": None, "suite_options": []})))
        run = _first_id(inferno("POST", "/test_runs", json.dumps({
            "test_session_id": session, "test_group_id": gid,
            "inputs": [{"name": "url", "value": AUCORE_SERVER, "type": "text"}]})))
        log(f"{suite} warmed via {gid}: status={_poll_run(run, suite)}")
    except Exception as e:
        log(f"{suite} warm failed (non-fatal): {e}")


def warm_all():
    if not inferno_ready():
        log("Inferno not reachable yet; skipping this warm cycle")
        return
    log("warming validator sessions through Inferno ...")
    warm_au_ps()
    for suite in AU_CORE_SUITES:
        warm_au_core(suite)
    log("warm cycle complete")


def main():
    log(f"sidecar starting (validator={VALIDATOR_URL}, inferno={INFERNO_URL})")
    wait_until(validator_ready, "validator")
    wait_until(inferno_ready, "inferno")
    warm_all()

    # Re-warm whenever the co-located validator restarts (unreachable -> reachable).
    up = True
    while True:
        time.sleep(RECHECK_INTERVAL)
        now = validator_ready()
        if now and not up:
            log("validator became reachable again after a restart -> re-warming")
            warm_all()
        up = now


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        # Never let the warmer take the validator pod down: idle forever on any fatal error.
        log(f"fatal error, idling (validator unaffected): {e}")
        while True:
            time.sleep(3600)
