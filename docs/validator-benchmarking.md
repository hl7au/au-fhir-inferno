# Validator benchmarking & session lifecycle

How to drive AU PS Inferno (and the validator-wrapper) programmatically against any
environment, the measured cold/warm/concurrent timings, and a quick reference for how
validator **sessions** and the **terminology cache** behave.

Companion to [`../VALIDATOR_OPTIMIZATION.md`](../VALIDATOR_OPTIMIZATION.md), which holds
the deployment model (single-pod Deployment, warmer) and the full decision history (§8).
This doc is the runnable tool + the numbers it produced.

## Tool: `scripts/psinferno.py`

Pure stdlib Python 3 + `kubectl` (only for the auto port-forward in `validate`). No gems, no venv.

| Command | What it does |
|---|---|
| `inferno`  | Replicates the UI flow: `POST /test_sessions` → `POST /test_runs` → poll → pass/fail/skip + wall time. |
| `validate` | Builds the exact body Inferno sends and POSTs straight to the validator `/validate`; auto port-forwards `svc/validator-api`. For cold/warm timing, concurrency, and A/B of `validationContext` options. |

Environments are built in (`--env dev|prod`); preview/PR via `--base-url` / `--validator-url`.

```bash
# Full Inferno session against dev with an example bundle
./scripts/psinferno.py inferno  --env dev  --bundle Bundle-aups-basicsummary.json

# Validator directly — cold (no session id), then warm (reuse the returned id)
./scripts/psinferno.py validate --env dev --bundle B.json
./scripts/psinferno.py validate --env dev --bundle B.json --session-id <id-from-previous>
```

`validate` defaults to Inferno's real behaviour (incl. `disableDefaultResourceFetcher: true`),
so A/B runs reflect production unless you opt out. Example bundles:
`~/.fhir/packages/hl7.fhir.au.ps#1.0.0-preview/package/example/Bundle-*.json`.

## There are TWO cold costs, not one

This is the key finding, confirmed by a no-prewarm load test on **prod** (fresh pod):

1. **Session engine build** — building the `ValidationEngine` (loads ~20+ IG/terminology
   packages). ~30–55s. Paid once per session id; held warm afterwards by
   `SESSION_CACHE_DURATION=-1`. Lost on a pod restart (in-memory).
2. **Terminology cache** — per-code `$validate`/expansion round-trips to tx.dev, cached on
   the **`terminology-cache` PVC**. This is what makes **concurrency** fast. It **persists
   across pod restarts** (it's on the PVC), so it's a one-time warm-up per *fresh* volume,
   not per restart.

The validator is **not** CPU-bound under load (CPU peaked ~2/3 cores in every test) — slow
concurrency is the cold terminology cache, where concurrent validations hit tx.dev for
uncached codes and serialise.

## Measured results

Single warm pod, 3 CPU / 12Gi, `Bundle-aups-basicsummary.json` (~30 KB) and
`Bundle-aups-referral-endoconsult-autogen.json` (~197 KB), 2026-06.

| Scenario | small (~30 KB) | large (~197 KB) |
|---|---|---|
| Cold session build (no prewarm) | ~33 s | ~53 s |
| Single **warm** validation (session + tx warm) | ~0.6 s | ~2.5–3 s |
| `conc=10`, **tx warm** | **~1.2–1.5 s** | **~13–22 s** |
| `conc=10`, **tx cold** (fresh PVC) | ~15 s | **~180 s** |
| Full Inferno suite (`suite_100preview`) | 6.7 s (94 pass / 33 skip / 2 omit) | — |

Takeaway: once **both** the session and the tx cache are warm, one pod comfortably serves
~10 concurrent event sessions. A cold tx cache is the only thing that makes concurrency
slow — and it persists on the PVC, so warming it once is durable.

### A/B: profile version is inert

`au-ps-bundle|1.0.0-ballot` vs `|1.0.0-preview` vs versionless → **identical** issue sets.
fhir-core resolves the canonical to the loaded `1.0.0-preview` SD regardless of the version
qualifier (locally, even with `disableDefaultResourceFetcher: true`). The stale `|1.0.0-ballot`
in au-ps-inferno's `bundle_module.rb` is behaviour-inert; pinning it to `preview` is hygiene.

## Session / cache lifecycle (quick reference)

- A **session id** is a server-generated **random UUID** (not a hash of the context).
  Inferno stores one id per **`(test_suite_id, suite_options, validator_name)`** in RDS and
  re-sends it. For AU PS that key is constant → all bundles, users, and `profile`/server
  inputs **share one session**.
- A **new** id (→ a cold session build) happens only when: first run for that key, or the
  stored id isn't in the pod's in-memory cache (pod restart, or LRU/time eviction —
  time-eviction disabled by `SESSION_CACHE_DURATION=-1`).
- The validator runs as a **single-pod Deployment** (`replicas: 1`): one cache, no cross-pod
  thrash, automatic failover when the pod is replaced. (Earlier 2-replica setups thrashed —
  see `VALIDATOR_OPTIMIZATION.md` §8.)
- **`baseEngine` does not help** — on the deployed core (6.6.3/6.9.7) cloning a preset's base
  engine is ~as slow as a full build (~35–45s), so it can't cheaply re-warm. Ruled out.

## Keeping it warm

- `SESSION_CACHE_DURATION=-1` holds the session warm while the pod lives.
- The **warmer CronJob** (`templates/validator-warmer.cronjob.yaml`) runs one validation
  through Inferno every ~30 min: re-warms the session after a restart (under the same id real
  users hit) and the tx cache, and doubles as an end-to-end synthetic health check.
- **Before a high-load event:** warm the **full** example set (not just the one warmer bundle)
  so the tx cache covers all the codes participants will use.

## Related

- [`../VALIDATOR_OPTIMIZATION.md`](../VALIDATOR_OPTIMIZATION.md) — deployment model, warmer,
  and the full investigation (§8: session lifecycle, multi-pod thrash, baseEngine dead-end,
  single-pod Deployment, load-test capacity).
