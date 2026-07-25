# validator-wrapper 1.0.79+ halves concurrent throughput against Ontoserver

**Status:** root-caused and measured here; not yet reported upstream.
**Effect:** ~1.95x slower at conc=10 from 1.0.79 onward. Validation results unchanged.
**Action taken:** chart held at **1.0.78** (`values.yaml`, `values-prod.yaml`).

> Read this before bumping `inferno.validatorImageUri`. The pin is a deliberate hold,
> not neglect.

---

## 1. What changed upstream

[validator-wrapper#247](https://github.com/hapifhir/org.hl7.fhir.validator-wrapper/pull/247),
released in **1.0.79**, upgrades `org.hl7.fhir.core` **6.9.7 → 6.9.11** and calls
`TerminologyClientContext.setCanUseCacheId(true)` at startup.

Quoting the PR's own description of the new core behaviour:

> Older FHIR Core clients generated arbitrary `cache-id` values and sent them as
> operation parameters. The updated terminology server only accepts cache identifiers it
> created through `$cache-control`. [...] FHIR Core 6.9.11 implements the new protocol:
> 1. Detect whether the server advertises `$cache-control`.
> 2. Call `$cache-control` to start a cache.
> 3. Receive a server-issued cache identifier.
> 4. Send that identifier as the `X-Cache-Id` HTTP header.
> 5. **Stop generating or sending arbitrary cache IDs as operation parameters.**

Step 5 is the problem. The legacy path was **removed**, not kept as a fallback.

## 2. Why it hurts us specifically

The change was made for **tx.fhir.org**, which adopted the new protocol. We point at
**`tx.dev.hl7.org.au`**, which is **Ontoserver 6.25.2** and does **not** advertise
`$cache-control`. Verified from its CapabilityStatement (2026-07-25):

```
$ curl -s "https://tx.dev.hl7.org.au/fhir/metadata?_summary=true"
software: Ontoserver® 6.25.2
server-level operations: closure, convert, diff, versions, x-load-package
                         ^ no cache-control
```

So from 1.0.79 the client finds no `$cache-control`, declines to fall back, and sends no
cache id at all. Server-side terminology caching is effectively **off**, and every code
check pays a full round trip. That is the opposite of the intent, for any
Ontoserver-backed deployment.

This matters here more than most: `docs/validator-benchmarking.md` already established
that terminology round trips, not CPU, are the concurrency limiter for this validator
(conc=10 on a large bundle: ~13s tx-warm vs ~180s tx-cold at only ~1.7/3 cores).

## 3. Measurements

All on the same chart, same `-Xmx5g`, same warm session, same 23KB AU PS bundle,
batches interleaved so terminology-server drift affects arms equally.

**Version bisect**, all on one node (m6a.xlarge, 4 vCPU) — conc=10 mean wall:

| wrapper | core | conc=10 |
|---|---|---|
| 1.0.78 | 6.9.7 | **2.58s** |
| **1.0.79** | **6.9.11** | **4.82s** ← regression enters |
| 1.0.81 | 6.9.12 | 4.91s |

1.0.79 and 1.0.81 agree within 2%; 1.0.80's core 6.9.12 bump contributes nothing
measurable. The whole cost arrives with #247.

**Crossover**, versions swapped between two previews to separate wrapper from hardware:

| conc=10 mean | 1.0.78 | 1.0.81 |
|---|---|---|
| m6a.large (2 vCPU) | 2.64s | 5.25s |
| m6a.xlarge (4 vCPU) | 2.58s | 4.91s |

The cost follows the **version**: 1.0.78 varies 2% across node types, 1.0.81 varies 6%,
and 1.0.81 is ~1.95x 1.0.78 on both. **1.0.78 won all 12 paired rounds.** Node type
accounts for at most ~6%.

**Not affected:**

- **Cold start** — warm PVC, cold session, 3 cycles per arm: 1.0.81 `60.1 / 52.5 / 52.7`
  vs 1.0.78 `48.3 / 49.1 / 54.3`, overlapping. In the crossover the slower cold start
  followed the *node*, so cold start is hardware-bound, not version-bound.
- **Correctness** — identical 53-issue outcomes on all 24 conc=10 batches, and a full
  AU Core v2.1.0-draft run gives **487 pass / 20 fail / 26 skip** on both 6.9.7 and
  6.9.12. Zero engine reloads, zero profile-resolve errors.

**`TERMINOLOGY_CLIENT_USE_CACHE_ID` does not rescue it.** Disabling it on 1.0.81 makes
things *worse* (conc=10 ~4.62s vs ~3.10s in that pairing), consistent with it disabling
the mechanism outright rather than restoring the legacy path. The chart exposes the knob
(`validator.terminologyClientUseCacheId`) but leaves it unset.

## 4. Options

1. **Add `$cache-control` to Ontoserver.** `tx.dev.hl7.org.au` is CSIRO/AEHRC's own
   server and the Ontoserver team is reachable. This unblocks the entire 1.0.79+ line for
   every Ontoserver-backed deployment, not just ours, and is arguably where the gap now
   sits given tx.fhir.org has moved. **Preferred.**
2. **Upstream fix in `org.hl7.fhir.core`** — retain the legacy client-generated cache-id
   path when the server does not advertise `$cache-control`, instead of disabling caching.
   Correct, but slower to land and needs a reproduction outside our deployment.
3. **Stay on 1.0.78.** What we do today. Costs nothing measurable: results are identical
   and cold start is unaffected. The only thing forgone is core 6.9.12, which brought no
   AU Core behaviour change we can observe.

Note that 1.0.78 is not merely "old": it carries the `ReentrantLock` + 5-minute cooldown
around the heap-pressure engine reload that 1.0.68 lacked, which is why the hold is at
.78 specifically and not further back.

## 5. Before reporting upstream

- Reproduce against a non-Ontoserver server lacking `$cache-control` so the report does
  not depend on our deployment.
- Capture the actual tx request volume (1.0.78 vs 1.0.79) to evidence the mechanism
  directly rather than inferring it from wall time. Our evidence is wall-clock plus the
  CapabilityStatement, which is strong but circumstantial about the request path.
- Confirm current `main` still removes the fallback; this was verified at 6.9.11/6.9.12
  only.
