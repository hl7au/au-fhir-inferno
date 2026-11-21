#!/usr/bin/env python3
"""Load FHIR test data into a FHIR server in dependency order.

Reads every FHIR JSON resource under the given paths (for example the AU Core folder of
https://github.com/hl7au/au-fhir-test-data) and writes each one to the server with
PUT [base]/[type]/[id], so ids stay the same and a rerun updates instead of duplicating.

Order matters on servers that check references on write: a resource is written only after
everything it references. Resources that reference each other in a cycle (a Patient and a
RelatedPerson that point at each other, for example) are written together in one
transaction Bundle, because no order of single writes can satisfy both.

Python 3.9 or later, standard library only.

    python3 load_test_data.py --base-url http://localhost:8080/fhir \\
        --resolve-from au-fhir-test-data/au-fhir-test-data-set \\
        au-fhir-test-data/au-fhir-test-data-set/au-core
"""

import argparse
import json
import re
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, wait
from graphlib import TopologicalSorter
from pathlib import Path

FHIR_JSON = "application/fhir+json"
# Stop when this many writes have failed with one status before any write succeeded.
STOP_AFTER = 20
# A literal relative reference: Type/id, optionally pinned to a version.
RELATIVE_REF = re.compile(r"^([A-Z][A-Za-z]+)/([A-Za-z0-9\-.]{1,64})(/_history/[^/]+)?$")


def read_resources(paths):
    """Return {"Type/id": (path, resource)} for every FHIR resource found under paths."""
    found = {}
    for root in map(Path, paths):
        files = [root] if root.is_file() else sorted(root.rglob("*.json"))
        for path in files:
            try:
                resource = json.loads(path.read_text(encoding="utf-8"))
            except (OSError, ValueError) as err:
                sys.exit(f"cannot read {path}: {err}")
            if not isinstance(resource, dict) or "resourceType" not in resource:
                continue
            if "id" not in resource:
                sys.exit(f"{path} has no id; this loader writes every resource by id")
            key = f"{resource['resourceType']}/{resource['id']}"
            found.setdefault(key, (path, resource))
    return found


def references(resource):
    """Yield the Type/id of every literal relative reference in a resource.

    Includes references made by contained resources (a contained Medication can
    reference an Organization on the server); a reference to a contained resource
    itself ("#id") is not a Type/id and is left out. Skips the contents of Bundles (a
    document or collection Bundle resolves its own entries).
    """
    if resource.get("resourceType") == "Bundle":
        return
    stack = list(resource.values())
    while stack:
        node = stack.pop()
        if isinstance(node, list):
            stack.extend(node)
        elif isinstance(node, dict):
            ref = node.get("reference")
            if isinstance(ref, str):
                match = RELATIVE_REF.match(ref)
                if match:
                    yield f"{match[1]}/{match[2]}"
            # Only a string "reference" is the reference itself. An element named
            # "reference" can also hold a whole Reference (Consent.provision.data.reference),
            # so an object under that name is searched like any other.
            stack.extend(value for key, value in node.items() if not (key == "reference" and isinstance(value, str)))


def add_referenced(load, pool):
    """Pull into load every resource in pool that load references, directly or not."""
    pending = list(load)
    while pending:
        for target in references(load[pending.pop()][1]):
            if target not in load and target in pool:
                load[target] = pool[target]
                print(f"  adding {target} from {pool[target][0]} (referenced, not in the load set)")
                pending.append(target)


def strongly_connected(graph):
    """Tarjan's algorithm, iterative. Returns a list of sets of nodes."""
    index, low, on_stack, stack, groups = {}, {}, set(), [], []
    for start in sorted(graph):
        if start in index:
            continue
        work = [(start, iter(sorted(graph[start])))]
        index[start] = low[start] = len(index)
        stack.append(start)
        on_stack.add(start)
        while work:
            node, children = work[-1]
            child = next(children, None)
            if child is not None:
                if child not in index:
                    index[child] = low[child] = len(index)
                    stack.append(child)
                    on_stack.add(child)
                    work.append((child, iter(sorted(graph[child]))))
                elif child in on_stack:
                    low[node] = min(low[node], index[child])
                continue
            work.pop()
            if work:
                parent = work[-1][0]
                low[parent] = min(low[parent], low[node])
            if low[node] == index[node]:
                group = set()
                while True:
                    member = stack.pop()
                    on_stack.discard(member)
                    group.add(member)
                    if member == node:
                        break
                groups.append(group)
    return groups


def request(method, url, body, headers, retries=3):
    """Send one FHIR request. Return (status, parsed body or text)."""
    data = json.dumps(body).encode("utf-8") if body is not None else None
    for attempt in range(1, retries + 1):
        req = urllib.request.Request(url, data=data, method=method, headers={
            "Content-Type": FHIR_JSON, "Accept": FHIR_JSON, **headers})
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                return resp.status, resp.read().decode("utf-8", "replace")
        except urllib.error.HTTPError as err:
            status, text = err.code, err.read().decode("utf-8", "replace")
        except (urllib.error.URLError, TimeoutError, ConnectionError) as err:
            status, text = 0, str(err)
        if status not in (0, 429, 502, 503, 504) or attempt == retries:
            return status, text
        time.sleep(2 * attempt)
    return status, text


def outcome_text(text):
    """Shorten an OperationOutcome (or any error body) to one readable line."""
    try:
        issues = json.loads(text).get("issue", [])
        text = "; ".join(i.get("diagnostics") or i.get("details", {}).get("text", "") for i in issues)
    except (ValueError, AttributeError):
        pass
    return " ".join(text.split())[:400]


def write_group(base, group, load, headers):
    """Write one strongly connected group. Return (HTTP status, None or an error line)."""
    if len(group) == 1:
        key = next(iter(group))
        status, text = request("PUT", f"{base}/{key}", load[key][1], headers)
    else:
        # Each entry's fullUrl is the resource's own URL on the server, so a reference to
        # another member of the cycle resolves to that entry inside the transaction.
        bundle = {"resourceType": "Bundle", "type": "transaction", "entry": [
            {"fullUrl": f"{base}/{key}", "resource": load[key][1], "request": {"method": "PUT", "url": key}}
            for key in sorted(group)]}
        status, text = request("POST", base, bundle, headers)
    if 200 <= status < 300:
        return status, None
    return status, f"{', '.join(sorted(group))}: HTTP {status} {outcome_text(text)}"


def giving_up(failures, succeeded, first_statuses):
    """True when the first STOP_AFTER writes all failed the same way and none succeeded.

    That is a server that rejects every write (no update as create, or missing
    credentials), not a problem with particular resources, so going on would only print
    the same failure for every resource.
    """
    return not succeeded and failures >= STOP_AFTER and len(first_statuses) == 1


def wait_for_server(base, headers, timeout):
    deadline = time.monotonic() + timeout
    while True:
        status, _ = request("GET", f"{base}/metadata", None, headers, retries=1)
        if status == 200:
            return
        if time.monotonic() > deadline:
            sys.exit(f"{base}/metadata did not answer 200 within {timeout}s (last status {status})")
        time.sleep(5)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("paths", nargs="+", help="files or folders of FHIR JSON to load")
    parser.add_argument("--base-url", required=True, help="FHIR base URL, e.g. http://localhost:8080/fhir")
    parser.add_argument("--resolve-from", action="append", default=[], metavar="DIR",
                        help="also load resources from DIR that the load set references (repeatable)")
    parser.add_argument("--header", action="append", default=[], metavar="'Name: value'",
                        help="extra request header, e.g. an Authorization header (repeatable)")
    parser.add_argument("--workers", type=int, default=4, help="parallel writes (default 4)")
    parser.add_argument("--wait", type=int, default=300, metavar="SECONDS",
                        help="wait this long for [base]/metadata to answer (default 300)")
    parser.add_argument("--dry-run", action="store_true", help="print the write order, write nothing")
    args = parser.parse_args()

    base = args.base_url.rstrip("/")
    headers = dict(h.split(":", 1) for h in args.header)
    headers = {k.strip(): v.strip() for k, v in headers.items()}

    load = read_resources(args.paths)
    if not load:
        sys.exit("no FHIR resources found")
    if args.resolve_from:
        add_referenced(load, read_resources(args.resolve_from))

    graph = {key: {t for t in references(res) if t in load and t != key} for key, (_, res) in load.items()}
    missing = sorted({t for _, res in load.values() for t in references(res) if t not in load})
    for target in missing:
        print(f"  warning: {target} is referenced but not in the data; the server may reject what references it")

    groups = strongly_connected(graph)
    group_of = {key: i for i, group in enumerate(groups) for key in group}
    # TopologicalSorter hands out each group once everything it references is written,
    # so independent groups are written in parallel.
    sorter = TopologicalSorter({i: {group_of[t] for k in g for t in graph[k]} - {i}
                                for i, g in enumerate(groups)})
    cycles = sum(1 for g in groups if len(g) > 1)
    print(f"{len(load)} resources in {len(groups)} writes ({cycles} transaction Bundles for reference cycles)")

    if args.dry_run:
        for i in sorter.static_order():
            print("  " + ", ".join(sorted(groups[i])))
        return

    wait_for_server(base, headers, args.wait)
    sorter.prepare()
    started, failures, failed, done, succeeded = time.monotonic(), 0, 0, 0, 0
    first_statuses = set()  # the statuses of the failures before any write succeeded
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        running = {}
        while sorter.is_active() and not giving_up(failures, succeeded, first_statuses):
            for i in sorter.get_ready():
                running[pool.submit(write_group, base, groups[i], load, headers)] = i
            finished, _ = wait(running, return_when=FIRST_COMPLETED)
            for future in finished:
                i = running.pop(future)
                status, error = future.result()
                if error:
                    failures += 1
                    failed += len(groups[i])
                    if not succeeded:
                        first_statuses.add(status)
                    print(f"  FAILED {error}", flush=True)
                else:
                    succeeded += 1
                # Dependents still get their turn: the server decides whether it accepts them.
                sorter.done(i)
                done += len(groups[i])
                if done % 200 < len(groups[i]):
                    print(f"  {done}/{len(load)} written", flush=True)
        if sorter.is_active():
            pool.shutdown(wait=True, cancel_futures=True)
            print(f"stopping: the first {failures} writes all failed with HTTP {first_statuses.pop()} and "
                  "none succeeded. Check that the server accepts PUT to an id that does not exist yet "
                  "(update as create) and any authentication it needs; see the requirements in "
                  "README.md.", flush=True)
            sys.exit(1)

    elapsed = time.monotonic() - started
    print(f"{len(load) - failed} of {len(load)} resources written in {elapsed:.0f}s; "
          f"{failures} writes failed")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
