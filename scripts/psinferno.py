#!/usr/bin/env python3
"""
Drive AU PS Inferno programmatically, or hit the validator-wrapper directly.

Two subcommands:
  inferno   Replicate the UI flow (create session -> run suite/group -> poll -> summarise)
  validate  POST a bundle straight to the validator /validate endpoint (mirrors the exact
            body Inferno builds), for raw perf timing and A/B of validationContext options.

Works against any environment via --env {dev,prod} or an explicit --base-url / --validator-url.
For `validate` it auto port-forwards svc/validator-api in the env's namespace unless
--validator-url is given.

Examples:
  # Run the whole AU PS suite on dev with an example bundle, print pass/fail + timing
  ./psinferno.py inferno --env dev --bundle Bundle-aups-basicsummary.json

  # Hit dev validator directly, time it, see the OperationOutcome
  ./psinferno.py validate --env dev --bundle Bundle-aups-basicsummary.json

  # A/B the profile-version question on dev (behaviour-only, nothing deployed)
  ./psinferno.py validate --env dev --bundle B.json --profile 'http://hl7.org.au/fhir/ps/StructureDefinition/au-ps-bundle|1.0.0-ballot'
  ./psinferno.py validate --env dev --bundle B.json --profile 'http://hl7.org.au/fhir/ps/StructureDefinition/au-ps-bundle|1.0.0-preview'
"""
import argparse, json, subprocess, sys, time, urllib.request, urllib.error, socket, contextlib

ENVS = {
    "dev":  {"inferno": "https://development.inferno.sparked-fhir.com", "ns": "dev-inferno",  "suite": "suite_100preview"},
    "prod": {"inferno": "https://inferno.hl7.org.au",                   "ns": "prod-inferno", "suite": "suite_100preview"},
}
# AU PS suite cli_context (mirrors lib/au_ps_inferno/1.0.0-preview/100preview_suite.rb on top of
# inferno_core VALIDATIONCONTEXT_DEFAULTS). Keep disableDefaultResourceFetcher=true (Inferno default).
DEFAULT_PROFILE = "http://hl7.org.au/fhir/ps/StructureDefinition/au-ps-bundle"
AU_PS_CONTEXT = {
    "sv": "4.0.1", "doNative": False, "extensions": ["any"], "disableDefaultResourceFetcher": True,
    "igs": ["hl7.fhir.au.ps#1.0.0-preview"], "txServer": "https://tx.dev.hl7.org.au/fhir", "noEcosystem": True,
}


def http(method, url, body=None, timeout=620):
    data = body.encode() if isinstance(body, str) else body
    req = urllib.request.Request(url, data=data, method=method,
                                 headers={"Content-Type": "application/json", "Accept": "application/json"})
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read().decode(), time.time() - t0
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode(), time.time() - t0


def free_port():
    s = socket.socket(); s.bind(("127.0.0.1", 0)); p = s.getsockname()[1]; s.close(); return p


@contextlib.contextmanager
def port_forward(ns, svc="validator-api", remote=3500):
    lp = free_port()
    proc = subprocess.Popen(["kubectl", "port-forward", "-n", ns, f"svc/{svc}", f"{lp}:{remote}"],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(40):
            with contextlib.suppress(OSError):
                socket.create_connection(("127.0.0.1", lp), timeout=0.5).close()
                break
            time.sleep(0.25)
        else:
            raise RuntimeError(f"port-forward to {ns}/{svc} did not come up")
        yield f"http://127.0.0.1:{lp}"
    finally:
        proc.terminate()


def cfg(args):
    c = dict(ENVS.get(args.env, {})) if args.env else {}
    return c


# ---------- inferno subcommand ----------
def cmd_inferno(args):
    c = cfg(args)
    base = (args.base_url or c.get("inferno")).rstrip("/")
    suite = args.suite or c.get("suite")
    api = f"{base}/suites/api"
    bundle = open(args.bundle).read()

    # 1. create session
    st, body, _ = http("POST", f"{api}/test_sessions?test_suite_id={suite}",
                        json.dumps({"preset_id": None, "suite_options": []}))
    if st not in (200, 201):
        sys.exit(f"create session failed ({st}): {body[:400]}")
    session_id = json.loads(body)["id"]
    print(f"session: {session_id}  suite: {suite}  @ {base}")

    # 2. create run (whole suite, or a group/test)
    payload = {"test_session_id": session_id, "inputs": [
        {"name": "validate_against", "value": json.dumps(["au_ps_bundle"]), "type": "text"},
        {"name": "bundle_resource", "value": bundle, "type": "text"},
        {"name": "profile", "value": args.profile, "type": "text"},
    ]}
    if args.test:        payload["test_id"] = args.test
    elif args.group:     payload["test_group_id"] = args.group
    else:                payload["test_suite_id"] = suite
    st, body, _ = http("POST", f"{api}/test_runs", json.dumps(payload))
    if st not in (200, 201):
        sys.exit(f"create run failed ({st}): {body[:600]}")
    run_id = json.loads(body)["id"]
    print(f"run: {run_id}  (polling...)")

    # 3. poll until done
    t0 = time.time()
    while True:
        st, body, _ = http("GET", f"{api}/test_runs/{run_id}")
        run = json.loads(body)
        status = run.get("status")
        sys.stdout.write(f"\r  status={status:10s} {time.time()-t0:6.1f}s")
        sys.stdout.flush()
        if status in ("done", "cancelled", None):
            break
        if status == "waiting":
            print("\n  run is WAITING for input (unexpected for validation) — stopping")
            break
        time.sleep(args.poll)
    elapsed = time.time() - t0
    print(f"\n  finished in {elapsed:.1f}s")

    # 4. results
    st, body, _ = http("GET", f"{api}/test_runs/{run_id}/results")
    results = json.loads(body)
    counts = {}
    fails = []
    for r in results:
        outcome = r.get("result", "?")
        counts[outcome] = counts.get(outcome, 0) + 1
        if outcome in ("fail", "error"):
            tid = r.get("test_id") or r.get("test_group_id") or r.get("id")
            msgs = "; ".join(m.get("message", "")[:160] for m in (r.get("messages") or [])[:3])
            fails.append(f"    [{outcome}] {tid}: {msgs}")
    print("  results: " + "  ".join(f"{k}={v}" for k, v in sorted(counts.items())))
    if fails:
        print("  failures/errors:")
        print("\n".join(fails))
    print(f"\nUI: {base}/test_sessions/{session_id}")


# ---------- validate subcommand ----------
def cmd_validate(args):
    c = cfg(args)
    bundle = open(args.bundle).read()
    try:
        rid = json.loads(bundle).get("id", "resource")
        rtype = json.loads(bundle).get("resourceType", "Bundle")
    except Exception:
        rid, rtype = "resource", "Bundle"

    ctx = dict(AU_PS_CONTEXT)
    if args.igs:   ctx["igs"] = args.igs
    if args.tx:    ctx["txServer"] = args.tx
    if args.fetch is not None:
        ctx["disableDefaultResourceFetcher"] = not args.fetch  # --fetch enables web fetch
    ctx["profiles"] = [args.profile]
    body = json.dumps({
        ("validationContext" if not args.cli_context_key else "cliContext"): ctx,
        "filesToValidate": [{"fileName": f"{rtype}/{rid}.json", "fileContent": bundle, "fileType": "json"}],
        "sessionId": args.session_id,
    })

    def do(validator_url):
        url = validator_url.rstrip("/") + "/validate"
        print(f"POST {url}")
        print(f"  profile={args.profile}")
        print(f"  igs={ctx['igs']} tx={ctx['txServer']} disableDefaultResourceFetcher={ctx['disableDefaultResourceFetcher']} sessionId={args.session_id}")
        st, resp, dt = http("POST", url, body)
        print(f"  HTTP {st} in {dt:.2f}s")
        try:
            j = json.loads(resp)
        except Exception:
            print("  (non-JSON response)\n" + resp[:800]); return
        sid = j.get("sessionId")
        print(f"  sessionId returned: {sid}")
        issues = (j.get("outcomes") or [{}])[0].get("issues") or []
        sev = {}
        for i in issues:
            lv = (i.get("level") or "?").lower(); sev[lv] = sev.get(lv, 0) + 1
        print("  issues: " + ("  ".join(f"{k}={v}" for k, v in sorted(sev.items())) or "none"))
        for i in issues:
            lv = (i.get("level") or "?").lower()
            if lv in ("error", "fatal", "warning") or args.verbose:
                print(f"    [{lv}] {i.get('location')}: {i.get('message','')[:220]}")

    if args.validator_url:
        do(args.validator_url)
    else:
        with port_forward(c["ns"]) as vurl:
            do(vurl)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    pi = sub.add_parser("inferno", help="drive a full Inferno test session")
    pi.add_argument("--env", choices=ENVS)
    pi.add_argument("--base-url", help="override Inferno base URL (e.g. a preview env)")
    pi.add_argument("--suite", help="test_suite_id (default per env)")
    pi.add_argument("--bundle", required=True, help="path to the FHIR Bundle JSON to validate")
    pi.add_argument("--profile", default=DEFAULT_PROFILE, help="profile input (versionless by default, as the UI sends)")
    pi.add_argument("--group", help="run only this test_group_id")
    pi.add_argument("--test", help="run only this test_id")
    pi.add_argument("--poll", type=float, default=2.0, help="poll interval seconds")
    pi.set_defaults(func=cmd_inferno)

    pv = sub.add_parser("validate", help="POST straight to the validator /validate endpoint")
    pv.add_argument("--env", choices=ENVS)
    pv.add_argument("--validator-url", help="validator base URL (skip port-forward)")
    pv.add_argument("--bundle", required=True)
    pv.add_argument("--profile", default=DEFAULT_PROFILE + "|1.0.0-preview")
    pv.add_argument("--igs", nargs="*", help="override IG list")
    pv.add_argument("--tx", help="override txServer URL")
    pv.add_argument("--fetch", dest="fetch", action="store_true", default=None,
                    help="ENABLE default resource fetcher (disableDefaultResourceFetcher=false). Default keeps Inferno's true.")
    pv.add_argument("--session-id", default=None, help="reuse a session id (test warm-cache hit)")
    pv.add_argument("--cli-context-key", action="store_true", help="send legacy 'cliContext' key instead of 'validationContext'")
    pv.add_argument("--verbose", action="store_true", help="print all issues incl info")
    pv.set_defaults(func=cmd_validate)

    args = ap.parse_args()
    if not getattr(args, "env", None) and not (getattr(args, "base_url", None) or getattr(args, "validator_url", None)):
        ap.error("provide --env or an explicit URL")
    args.func(args)


if __name__ == "__main__":
    main()
