#!/usr/bin/env python3
"""Find the concurrency at which an Inferno app tier stops serving new sessions.

This is a resource-exhaustion probe for YOUR OWN infrastructure. Do not point it at
anyone else's deployment. It ramps concurrent POST /test_sessions until success rate
collapses, so the same run shows the difference between a slow (unpatched) and fast
(patched) app tier.

Everything you would want to change lives in CONFIG below or on the command line.

  python3 dos_probe.py dev       # ramp against the dev target
  python3 dos_probe.py prod      # ramp against the prod target
  python3 dos_probe.py dev --steps 1,2,3,5,10 --suite au_ps_v100
  python3 dos_probe.py prod --once 10        # single burst of 10, no ramp
  python3 dos_probe.py prod --open 5         # warm single-user session open (POST+GET)

Latency shown is end to end from this machine (includes network + download).
"""
import argparse
import json
import ssl
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

# --------------------------------------------------------------------------------------
# CONFIG: edit these. Each target is one environment. `params`/`payload`/`headers` are
# per-target so a target that needs a JSON body (e.g. suite_options) can carry one.
# --------------------------------------------------------------------------------------
CONFIG = {
    "dev": {
        "base": "https://development.inferno.sparked-fhir.com",
        "path": "/suites/api/test_sessions",
        "params": {"test_suite_id": "au_core_v210_draft"},
        "payload": None,          # None -> empty POST body. Or a dict -> sent as JSON.
        "headers": {},
        "note": "has the available_inputs fix",
    },
    "prod": {
        "base": "https://inferno.sparked-fhir.com",
        "path": "/suites/api/test_sessions",
        "params": {"test_suite_id": "au_core_v210_draft"},
        "payload": None,
        "headers": {},
        "note": "no fix (pinned older image)",
    },
    # Example of a target that selects suite options via a JSON body. Left here as a
    # template; point it only at infrastructure you own.
    # "myenv": {
    #     "base": "https://inferno.example.internal",
    #     "path": "/suites/api/test_sessions",
    #     "params": {"test_suite_id": "us_core_v610"},
    #     "payload": {"suite_options": [
    #         {"id": "smart_app_launch_version", "value": "smart_app_launch_2_2"}]},
    #     "headers": {"Authorization": "Bearer ..."},
    #     "note": "",
    # },
}

DEFAULT_STEPS = [1, 2, 3, 5, 8, 10, 15, 20, 30]
REQUEST_TIMEOUT = 200           # generous, so we see the server's own timeout, not ours
SETTLE_SECONDS = 6              # pause between steps so the queue drains
CTX = ssl.create_default_context()


def build_request(t):
    url = t["base"].rstrip("/") + t["path"]
    if t.get("params"):
        url += "?" + urllib.parse.urlencode(t["params"])
    body, headers = b"", dict(t.get("headers") or {})
    if t.get("payload") is not None:
        body = json.dumps(t["payload"]).encode()
        headers.setdefault("Content-Type", "application/json")
    return url, body, headers


def one_request(url, body, headers, out, idx):
    t0 = time.time()
    req = urllib.request.Request(url, data=body, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT, context=CTX) as r:
            r.read(256)
            out[idx] = (r.status, time.time() - t0)
    except urllib.error.HTTPError as e:
        e.read(256)
        out[idx] = (e.code, time.time() - t0)          # 504 etc land here
    except Exception:
        out[idx] = ("ERR", time.time() - t0)


def burst(url, body, headers, conc):
    out = {}
    t0 = time.time()
    threads = [threading.Thread(target=one_request, args=(url, body, headers, out, i))
               for i in range(conc)]
    for th in threads:
        th.start()
    for th in threads:
        th.join()
    wall = time.time() - t0
    lat = sorted(d for _, d in out.values())
    ok = sum(1 for s, _ in out.values() if s == 200)
    codes = {}
    for s, _ in out.values():
        codes[s] = codes.get(s, 0) + 1
    p = lambda q: lat[min(int(len(lat) * q), len(lat) - 1)]
    return dict(conc=conc, wall=wall, ok=ok, p50=p(0.50), p95=p(0.95),
                mx=lat[-1], codes=codes)


def median(xs):
    xs = sorted(x for x in xs if x is not None)
    if not xs:
        return None
    n = len(xs)
    return xs[n // 2] if n % 2 else (xs[n // 2 - 1] + xs[n // 2]) / 2


def timed_request(url, body, headers, method):
    """One request. Returns (status, ttfb, total, raw_body).

    ttfb is time to the response headers, i.e. what a browser reports as "waiting for
    server". It already includes the server building the whole payload, because Inferno
    serialises the tree before sending the first byte. total additionally includes
    downloading the body, so a big response inflates total but not ttfb.
    """
    t0 = time.time()
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        r = urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT, context=CTX)
        ttfb = time.time() - t0
        raw = r.read()
        r.close()
        return r.status, ttfb, time.time() - t0, raw
    except urllib.error.HTTPError as e:
        ttfb = time.time() - t0
        raw = e.read()
        return e.code, ttfb, time.time() - t0, raw
    except Exception:
        now = time.time() - t0
        return "ERR", now, now, b""


def extract_session_id(raw):
    try:
        return json.loads(raw.decode()).get("id")
    except Exception:
        return None


def session_open(target_name, samples, warmups):
    """Measure the real single-user cost of opening a session: POST /test_sessions
    then GET /test_sessions/:id, warm and sequential (no concurrency). Both legs
    serialise the same tree, so this is what one user waits for with nobody else on
    the box. Times reported are server wait (TTFB), matching a browser's
    "waiting for server", so they exclude downloading the ~1MB body.
    """
    t = CONFIG[target_name]
    post_url, body, headers = build_request(t)
    get_base = t["base"].rstrip("/") + t["path"]

    print(f"target : {target_name}  ({t.get('note','')})")
    print(f"POST   : {post_url}")
    print(f"warmup : {warmups}   samples : {samples}   (sequential, no concurrency)")
    print("times are server wait (TTFB), matching a browser's 'waiting for server'\n")

    for _ in range(warmups):
        timed_request(post_url, body, headers, "POST")

    print(f"{'#':>2}  {'POST':>8} {'GET':>8} {'open':>8}  codes")
    print("-" * 44)
    posts, gets, opens = [], [], []
    for i in range(samples):
        pst, p_ttfb, _p_total, raw = timed_request(post_url, body, headers, "POST")
        sid = extract_session_id(raw)
        g_ttfb, gst = None, "-"
        if sid:
            gst, g_ttfb, _g_total, _ = timed_request(get_base + "/" + sid, None,
                                                      dict(headers), "GET")
        total = p_ttfb + g_ttfb if g_ttfb is not None else None
        posts.append(p_ttfb)
        gets.append(g_ttfb)
        opens.append(total)
        gtxt = f"{g_ttfb:>7.2f}s" if g_ttfb is not None else f"{'n/a':>8}"
        otxt = f"{total:>7.2f}s" if total is not None else f"{'n/a':>8}"
        print(f"{i + 1:>2}  {p_ttfb:>7.2f}s {gtxt} {otxt}  {{{pst}, {gst}}}")
        sys.stdout.flush()

    print("-" * 44)
    fmt = lambda v: f"{v:>7.2f}s" if v is not None else f"{'n/a':>8}"
    print(f"med {fmt(median(posts))} {fmt(median(gets))} {fmt(median(opens))}")


def open_flow(post_url, body, headers, get_base, out, idx):
    """One full session open as a real client does it: POST to create, then GET the
    new session. Records server-wait (TTFB) for each leg and the sum."""
    pst, p_ttfb, _p_total, raw = timed_request(post_url, body, headers, "POST")
    sid = extract_session_id(raw) if pst == 200 else None
    gst, g_ttfb = "-", None
    if sid:
        gst, g_ttfb, _g_total, _ = timed_request(get_base + "/" + sid, None,
                                                  dict(headers), "GET")
    out[idx] = dict(ok=(pst == 200 and gst == 200), post=p_ttfb, get=g_ttfb,
                    total=(p_ttfb + g_ttfb) if g_ttfb is not None else p_ttfb,
                    pst=pst, gst=gst)


def burst_open(post_url, body, headers, get_base, conc):
    out = {}
    t0 = time.time()
    threads = [threading.Thread(target=open_flow,
                                args=(post_url, body, headers, get_base, out, i))
               for i in range(conc)]
    for th in threads:
        th.start()
    for th in threads:
        th.join()
    wall = time.time() - t0
    totals = sorted(r["total"] for r in out.values())
    ok = sum(1 for r in out.values() if r["ok"])
    codes = {}
    for r in out.values():
        k = f"{r['pst']}/{r['gst']}"
        codes[k] = codes.get(k, 0) + 1
    p = lambda q: totals[min(int(len(totals) * q), len(totals) - 1)]
    return dict(conc=conc, wall=wall, ok=ok,
                post=median([r["post"] for r in out.values()]),
                get=median([r["get"] for r in out.values()]),
                p50=p(0.50), p95=p(0.95), mx=totals[-1], codes=codes)


def open_ramp(target_name, steps, warmups):
    """Ramp concurrency, but each unit of load is a full session open (POST+GET), not a
    bare POST. Per level: median POST and GET server-wait, and p50/p95/max of the whole
    open. Shows how the ~10s single-user open degrades as concurrent users pile on."""
    t = CONFIG[target_name]
    post_url, body, headers = build_request(t)
    get_base = t["base"].rstrip("/") + t["path"]

    print(f"target : {target_name}  ({t.get('note','')})")
    print(f"open   : POST {post_url}  then GET .../:id")
    print("times are server wait (TTFB); POST/GET are per-leg medians, "
          "p50/p95/max are the full open\n")
    print(f"{'conc':>4} {'ok':>9} {'wall':>7} {'POST':>7} {'GET':>7} "
          f"{'p50':>7} {'p95':>7} {'max':>7}  codes")
    print("-" * 82)

    for _ in range(warmups):
        open_flow(post_url, body, headers, get_base, {}, 0)

    for c in steps:
        r = burst_open(post_url, body, headers, get_base, c)
        flag = "" if r["ok"] == c else "  <-- failures"
        gtxt = f"{r['get']:>6.2f}s" if r["get"] is not None else f"{'n/a':>7}"
        print(f"{r['conc']:>4} {r['ok']:>4}/{r['conc']:<4} {r['wall']:>6.1f}s "
              f"{r['post']:>6.2f}s {gtxt} {r['p50']:>6.2f}s {r['p95']:>6.2f}s "
              f"{r['mx']:>6.2f}s  {r['codes']}{flag}")
        sys.stdout.flush()
        if c != steps[-1]:
            time.sleep(SETTLE_SECONDS)


def run(target_name, steps, once):
    t = CONFIG[target_name]
    url, body, headers = build_request(t)
    print(f"target : {target_name}  ({t.get('note','')})")
    print(f"POST   : {url}")
    if body:
        print(f"body   : {body.decode()}")
    print()
    print(f"{'conc':>5} {'ok':>9} {'wall':>7} {'p50':>7} {'p95':>7} {'max':>7}  codes")
    print("-" * 74)

    seq = [once] if once else steps
    for c in seq:
        r = burst(url, body, headers, c)
        flag = "" if r["ok"] == c else "  <-- failures"
        print(f"{r['conc']:>5} {r['ok']:>4}/{r['conc']:<4} {r['wall']:>6.1f}s "
              f"{r['p50']:>6.2f}s {r['p95']:>6.2f}s {r['mx']:>6.2f}s  {r['codes']}{flag}")
        sys.stdout.flush()
        if not once and r["ok"] < c:
            print(f"\nservice degraded at concurrency {c} for target '{target_name}'")
            break
        if not once:
            time.sleep(SETTLE_SECONDS)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("target", choices=list(CONFIG), help="which environment to probe")
    ap.add_argument("--steps", help="comma separated concurrency ramp, e.g. 1,2,5,10")
    ap.add_argument("--once", type=int, help="single burst of N, no ramp")
    ap.add_argument("--open", type=int, metavar="N",
                    help="measure warm single-user session open (POST+GET), N samples")
    ap.add_argument("--open-ramp", action="store_true",
                    help="ramp concurrency where each unit of load is a full open (POST+GET)")
    ap.add_argument("--warmup", type=int, default=1,
                    help="throwaway requests before timing (default 1)")
    ap.add_argument("--suite", help="override test_suite_id for this run")
    args = ap.parse_args()

    if args.suite:
        CONFIG[args.target]["params"] = dict(CONFIG[args.target].get("params") or {},
                                             test_suite_id=args.suite)
    steps = [int(x) for x in args.steps.split(",")] if args.steps else DEFAULT_STEPS
    if args.open_ramp:
        open_ramp(args.target, steps, args.warmup)
        return
    if args.open is not None:
        session_open(args.target, args.open, args.warmup)
        return
    run(args.target, steps, args.once)


if __name__ == "__main__":
    main()