#!/usr/bin/env python3
"""Run an Inferno test suite headless through the Inferno JSON API and compare with a baseline.

Creates a test session, starts a run of the whole suite with the given inputs, waits for
it to finish, then reads every test result. A regression is a test whose result is
"fail" or "error" in this run and was not "fail" or "error" in the baseline file (a test
the baseline does not list counts too). The script exits 1 when there is a regression, so
the CI job fails; it says nothing about whether a server meets a specification.

Python 3.9 or later, standard library only.

    python3 run_inferno.py --inferno http://localhost:4567/suites --suite au_core_v200 \\
        --input url=http://fhir-server:8080/fhir --baseline inferno-baseline.json

Exit codes: 0 no regressions, 1 regressions, 2 the run could not be completed (including
any error talking to Inferno).

With --output, the results are written without each result's inputs and outputs, which
Inferno returns with their values and which can hold a credential.
"""

import argparse
import collections
import http.client
import json
import os
import sys
import time
import traceback
import urllib.error
import urllib.request

NOT_OK = {"fail", "error"}


def api(base, method, path, body=None):
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(f"{base}/api/{path}", data=data, method=method,
                                 headers={"Content-Type": "application/json", "Accept": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            text = resp.read()
        # Some calls answer with no body, such as DELETE test_runs/{id} (204).
        return json.loads(text) if text.strip() else {}
    except urllib.error.HTTPError as err:
        stop(f"{method} {path}: HTTP {err.code} {err.read().decode('utf-8', 'replace')[:500]}")
    except (OSError, http.client.HTTPException) as err:
        # URLError, timeouts and dropped connections, for example while Inferno restarts.
        stop(f"{method} {path}: no answer from Inferno ({err})")
    except ValueError as err:
        stop(f"{method} {path}: Inferno's answer is not JSON ({err})")


def stop(message):
    print(f"error: {message}", file=sys.stderr)
    sys.exit(2)


def wait_for_suite(base, suite_id, timeout):
    deadline = time.monotonic() + timeout
    while True:
        try:
            with urllib.request.urlopen(f"{base}/api/test_suites/{suite_id}", timeout=30) as resp:
                return json.loads(resp.read())
        except (OSError, http.client.HTTPException, ValueError) as err:
            if isinstance(err, urllib.error.HTTPError) and err.code == 404:
                stop(f"Inferno does not offer suite {suite_id!r}; see {base}/api/test_suites")
            if time.monotonic() > deadline:
                stop(f"Inferno at {base} did not answer within {timeout}s ({err})")
            time.sleep(5)


def parse_inputs(items):
    """Turn NAME=VALUE arguments into a dict."""
    given = {}
    for number, item in enumerate(items, 1):
        name, sep, value = item.partition("=")
        if not sep or not name:
            # Say which one, not what it holds: it can be a credential.
            stop(f"--input number {number} is not NAME=VALUE")
        given[name] = value
    return given


def without_io(results):
    """Copy the results without each result's inputs and outputs.

    Inferno returns every input a test was given with its value, so a token passed as
    an input (header_value, smart_credentials) would otherwise land in the file.
    """
    return [{k: v for k, v in r.items() if k not in ("inputs", "outputs")} for r in results]


def walk(group, titles):
    """Record "short_id title" for every group and test, keyed by id."""
    for child in group.get("test_groups", []) + group.get("tests", []):
        titles[child["id"]] = f"{child.get('short_id', '')} {child.get('title', '')}".strip()
        walk(child, titles)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--inferno", default=os.environ.get("INFERNO_URL", "http://localhost:4567/suites"),
                        help="Inferno base, including its base path (default $INFERNO_URL, "
                             "else http://localhost:4567/suites)")
    parser.add_argument("--suite", required=True, help="suite id, e.g. au_core_v200")
    parser.add_argument("--input", action="append", default=[], metavar="NAME=VALUE",
                        help="suite input; inputs not given keep the suite's default (repeatable)")
    parser.add_argument("--baseline", help="baseline JSON from an earlier --write-baseline")
    parser.add_argument("--write-baseline", metavar="PATH", help="write this run's results as a baseline")
    parser.add_argument("--output", metavar="PATH",
                        help="write the session results here, without each result's inputs and outputs")
    parser.add_argument("--timeout", type=int, default=3600, metavar="SECONDS",
                        help="give up on the run after this long (default 3600)")
    args = parser.parse_args()
    base = args.inferno.rstrip("/")

    suite = wait_for_suite(base, args.suite, timeout=600)
    given = parse_inputs(args.input)
    unknown = set(given) - {i["name"] for i in suite.get("inputs", [])}
    if unknown:
        stop(f"suite {args.suite} has no input named {', '.join(sorted(unknown))}")
    inputs = []
    for definition in suite.get("inputs", []):
        value = given.get(definition["name"], definition.get("default"))
        if value not in (None, ""):
            inputs.append({"name": definition["name"], "value": value})
    # Names only: an input can carry a credential.
    print(f"inputs given: {', '.join(sorted(given)) or 'none'}; the rest keep the suite defaults")

    session = api(base, "POST", "test_sessions", {"test_suite_id": args.suite})
    print(f"session {session['id']} for {args.suite} (suite version {suite.get('version')})")
    run = api(base, "POST", "test_runs",
              {"test_session_id": session["id"], "test_suite_id": args.suite, "inputs": inputs})

    started = time.monotonic()
    status = run["status"]
    while status in ("queued", "running"):
        if time.monotonic() - started > args.timeout:
            api(base, "DELETE", f"test_runs/{run['id']}")
            stop(f"the run did not finish within {args.timeout}s; it was cancelled")
        time.sleep(15)
        status = api(base, "GET", f"test_runs/{run['id']}")["status"]
        print(f"  {time.monotonic() - started:5.0f}s {status}", flush=True)
    if status != "done":
        stop(f"the run ended with status {status!r}; a CI run needs a suite that runs without user input")
    print(f"run finished in {time.monotonic() - started:.0f}s")

    results = api(base, "GET", f"test_sessions/{session['id']}/results")
    if args.output:
        with open(args.output, "w", encoding="utf-8") as out:
            json.dump(without_io(results), out, indent=2)

    titles = {}
    walk(suite, titles)
    tests = {r["test_id"]: r for r in results if "test_id" in r}
    groups = {r["test_group_id"]: r for r in results if "test_group_id" in r}
    counts = collections.Counter(r["result"] for r in tests.values())
    print(f"{len(tests)} tests: " + ", ".join(f"{n} {k}" for k, n in sorted(counts.items())))
    if not tests:
        stop("the run produced no test results")

    baseline = {}
    if args.baseline:
        try:
            with open(args.baseline, encoding="utf-8") as f:
                baseline = json.load(f)["results"]
        except (OSError, ValueError, KeyError) as err:
            stop(f"cannot read baseline {args.baseline} ({err}); create one with --write-baseline")
    def by_number(test_id):
        """Sort key: the test's short id (1.2.10) as numbers, so 1.2.9 comes before 1.2.10."""
        number = titles.get(test_id, "").split(" ")[0]
        return [int(n) for n in number.split(".") if n.isdigit()], test_id

    regressions = sorted((t for t, r in tests.items() if r["result"] in NOT_OK and baseline.get(t) not in NOT_OK),
                         key=by_number)
    fixed = sorted((t for t, r in baseline.items() if r in NOT_OK and tests.get(t, {}).get("result") not in NOT_OK),
                   key=by_number)

    lines = [f"## Inferno {args.suite}", "",
             f"{len(tests)} tests: " + ", ".join(f"{n} {k}" for k, n in sorted(counts.items())), "",
             "| Group | Result |", "| --- | --- |"]
    # The suite's groups and the groups one level down (in AU Core, one per resource type).
    for group in suite.get("test_groups", []):
        for g in [group] + group.get("test_groups", []):
            if g["id"] in groups:
                lines.append(f"| {titles[g['id']]} | {groups[g['id']]['result']} |")
    if args.baseline:
        lines += ["", f"Regressions against the baseline: {len(regressions)}"]
    else:
        lines += ["", f"No baseline given, so every test that failed or errored is listed: {len(regressions)}"]
    for t in regressions:
        message = tests[t].get("result_message", "").replace("\n", " ")[:300]
        lines.append(f"- {titles.get(t, t)} ({tests[t]['result']}, baseline {baseline.get(t, 'absent')}): {message}")
    if fixed:
        lines += ["", f"No longer fail or error ({len(fixed)}); refresh the baseline to keep them that way:"]
        lines += [f"- {titles.get(t, t)}" for t in fixed]
    report = "\n".join(lines)
    print(report)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as summary:
            summary.write(report + "\n")

    if args.write_baseline:
        with open(args.write_baseline, "w", encoding="utf-8") as out:
            json.dump({"suite": args.suite, "suite_version": suite.get("version"),
                       "results": {t: r["result"] for t, r in sorted(tests.items())}}, out, indent=2)
            out.write("\n")
        print(f"baseline written to {args.write_baseline}")
    # Writing a baseline records the run as it is, so it does not fail the step.
    sys.exit(1 if regressions and not args.write_baseline else 0)


if __name__ == "__main__":
    # Exit code 1 means a regression, so an unexpected error must not exit with it.
    try:
        main()
    except Exception:  # noqa: BLE001
        traceback.print_exc()
        sys.exit(2)
