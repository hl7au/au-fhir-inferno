# Brief: 10 concurrent suite runs fail with 504 at the Inferno app tier

**Status:** reproduced twice, root cause unknown. Not investigated.
**Scope:** Inferno app / worker / Postgres tier. **Not** the validator — that was cleared.
**Written for:** a fresh session, so the facts below are established and need not be re-derived.

---

## 1. The symptom

Driving **10 concurrent AU Core v2.1.0-draft suite runs** at a preview environment fails
completely. Every run returns `504 upstream request timeout` from nginx, on both
`POST /suites/api/test_sessions` and `POST /suites/api/test_runs`.

Reproduced twice:

| attempt | launch pattern | wall | completed |
|---|---|---|---|
| 1 | all 10 simultaneous | 29.5s | **0/10** |
| 2 | staggered 3s apart | 42.2s | **0/10** |

**Staggering did not help**, so it is not a simple thundering herd on connection accept.

## 2. What has been ruled out

**The validator is not involved.** Through both failed runs it logged zero engine reloads,
zero low-memory warnings, zero profile-resolve errors, and never restarted. A single suite
run through the same environment succeeds normally (AU Core v2.1.0-draft: 565s,
487 pass / 20 fail / 26 skip; AU Core v2.0.0: 460s, 432/14/9). Validator-level `conc=10`
straight to `/validate` also works fine (~2.6s wall, all 200, one shared session).

So the failure is upstream of the validator, in the Inferno app tier.

## 3. Established facts about that tier

| | prod | preview (at time of test) |
|---|---|---|
| `inferno-app` replicas | 1 (HPA 1→6 @ 70% CPU) | 1 (HPA disabled) |
| `inferno-app` limits | 2 CPU / 1536Mi | 2 CPU / 1536Mi |
| `inferno-worker` replicas | **2** | 1 |
| `inferno-worker` limits | 1 CPU / 1536Mi | 1 CPU / 1536Mi |
| `inferno-worker` probes | **none — no liveness, no readiness** | none |
| Postgres | RDS | in-namespace, 128Mi request |

Two things stand out:

- **`inferno-worker` has no liveness or readiness probe at all** (verified on prod). A second
  session separately observed `reason=Error` worker exits across `inferno-pr-150`, `-155`
  and `-156`, i.e. real process exits with nothing gating restarts.
- **The HPA cannot help a burst of this shape.** Prod's `inferno-app` sits at 1 replica /
  0% CPU. HPA scale-up takes ~15-30s minimum to observe, decide and schedule; both failures
  completed in 29-42s. So prod would likely 504 the same way despite autoscaling.

## 4. Hypotheses, roughly in order

1. **Single-replica app tier saturating.** Ten concurrent session+run creations against one
   Puma. Cheapest test: raise `inferno.replicas` on a preview and retry.
2. **Node contention (preview-specific).** The preview validator reserved 6Gi of an
   `m6a.large`'s 6.9Gi allocatable, squeezing app, worker, nginx and Postgres onto the
   remainder. **This has since changed** — au-fhir-inferno#156 and sparked-argo#162 drop the
   preview validator to a 3Gi request — so **re-test before assuming the 504 still exists.**
3. **Postgres.** The preview DB requests 128Mi and shares that contended node. Slow queries
   would stall session creation directly.
4. **DB growth on prod (untested, and the interesting one).** Prod's Inferno DB has months of
   `test_sessions` / `results` / `requests` rows; previews start empty. If session creation
   does unindexed or N+1 queries, it degrades as the table grows. Note this would *not*
   explain the preview failures (fresh DB), so there may be **two different causes**.

   > **Disambiguate first:** "prod takes longer to spin up a session" could mean the *Inferno
   > test session* (a DB row, where this hypothesis applies) or the *validator session* (an
   > engine build, where the DB is irrelevant). The validator-session cold build measured
   > 45-60s on preview and 33-53s on prod, i.e. prod is if anything **faster**, so if prod
   > genuinely feels slower it is likely the DB-backed one.

## 5. Which layer would change

- **`au-fhir-inferno` chart** — most likely: app replicas, worker probes, Postgres sizing,
  HPA behaviour (`scaleUp` stabilisation window / policies).
- **`inferno_core`** — if session or run creation is inefficient (N+1, missing index on
  `test_sessions` / `results` / `requests`). Would need an upstream issue; check query plans
  against a prod-sized DB first.
- **Test kits** — unlikely to be implicated in an HTTP timeout at session creation.

## 6. Reproduction

Harnesses used, all pure stdlib Python 3, in `/tmp` at time of writing (re-create as needed):

- `stress156.py` — AU PS ×1, then AU Core 2.1.0-draft ×10 concurrent, then AU Core 2.0.0 ×1
- `stress2.py` — same with configurable stagger
- `memsampler.sh` — samples validator live heap / committed / RSS / GC / reloads every 15s

Target `https://pr-<n>.preview.inferno.sparked-fhir.com`, FHIR server
`https://smile.sparked-fhir.com/aucore/fhir/DEFAULT`.

**Caveat that will bite:** previews now run `sessionCacheSize: 1` (sparked-argo#159), so a
multi-suite stress run thrashes by design — each suite switch rebuilds an engine (~50s). For
concurrency testing of a *single* suite this is fine, since Inferno keys one validator
session per `(test_suite_id, suite_options, validator_name)` and all concurrent runs of one
suite share it. For multi-suite testing, raise the cap on that PR via a one-line
sparked-argo change (the ApplicationSet's inline values beat the chart's, so a test PR
cannot raise it alone). `javaOpts` **is** per-PR overridable.

## 7. First three steps

1. Stand up a preview on current `master` and **re-run the 10-concurrent test** — the
   validator request dropping 6Gi → 3Gi may have resolved the node contention outright.
2. If it still fails, bisect the tier: raise `inferno.replicas` to 3, retry; then raise
   Postgres resources, retry. Cheap and decisive.
3. Separately, measure `POST /test_sessions` latency on prod versus a fresh preview, and
   compare table sizes and query plans. That tests the DB-growth hypothesis independently of
   the 504s.
