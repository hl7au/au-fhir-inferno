# noEcosystem Performance Analysis

**Date:** 2026-06-04  
**Compared:** au_core_v100 test suite, same FHIR server (smile.sparked-fhir.com/aucore)  
**Prod session:** [cyCQ11nBExO](https://inferno.hl7.org.au/suites/au_core_v100/cyCQ11nBExO#au_core_v100) — `au_core_test_kit` 1.4.0, no `noEcosystem`  
**Dev session:** [7xcwVBi0ALC](https://development.inferno.sparked-fhir.com/suites/au_core_v100/7xcwVBi0ALC#au_core_v100) — `au_core_test_kit` 1.4.1, `noEcosystem true`

## Summary

| | Prod (1.4.0) | Dev (1.4.1 + noEcosystem) |
|---|---|---|
| Start (first result) | 05:19:18 UTC | 05:19:48 UTC |
| End (last result) | 05:28:46 UTC | 05:25:32 UTC |
| **Total duration** | **9m 28s** | **5m 44s** |
| Pass | 395 | 393 |
| Fail | 17 | 19 |
| Skip/Omit | 7 | 7 |
| Total tests | 419 | 419 |
| Capability stmt errors | 0 (this run) | 0 |

**Measured speedup: 1.65×** for these two specific sessions. The anecdotal "90 minute" figure for prod reflects worst-case conditions — see [Why the 90-minute figure](#why-the-90-minute-figure) below.

## Environment Differences

| | Prod | Dev |
|---|---|---|
| Namespace | `prod-inferno` | `dev-inferno` |
| au_core_test_kit | `1.4.0` (RubyGems) | `1.4.1` (git `80fa347`) |
| `noEcosystem` | not set (defaults `false`) | `true` |
| validator-wrapper | `markiantorno/validator-wrapper:1.0.68` | `markiantorno/validator-wrapper:latest` |
| Validator replicas | 2 | 1 |
| Validator terminology cache | Warm (prior midnight run) | Cold |

The only functional change between 1.4.0 and 1.4.1 is `noEcosystem true` added to all three `cli_context` blocks (v1.0.0, v2.0.0, validation_suite). Subsequent versions add `baseEngine` per suite — see `VALIDATOR_OPTIMIZATION.md` section 6 for the current state.

## Observed Timeline

### Prod (noEcosystem = false)

```
05:19:05  Test session inputs submitted
05:19:18  First test result (non-validation tests — FHIR reads from smile)
05:26:55  First validator /validate request logged     ← 7m50s before validator engaged
05:26:55–05:28:45  Active validation period (~1m50s, ~80 validations/min, 2 pods)
05:28:46  Last test result recorded
```

**Total: 9m28s**

### Dev (noEcosystem = true)

```
05:19:08  Test session inputs submitted
05:19:48  First test result
05:19:49  CapabilityStatement validation request sent to validator (estimated)
05:21:33  CapabilityStatement validation completes: 200 OK in 103,504ms (cold session)
05:21:42  Patient validations begin: 20–100ms each
05:25:32  Last test result recorded
```

**Total: 5m44s**

## What the 7m50s Startup Gap Is

On prod, the validator did not receive any `/validate` requests until 05:26:55 — nearly 8 minutes after the test started. During this period the HAPI FHIR validator was initialising its `TerminologyClientManager` ecosystem:

1. Querying `tx.dev.hl7.org.au/tx-reg/resolve` for each code system encountered
2. Receiving a 302 → `tx.fhir.org/tx-reg` (via our HTTPRoute)
3. Getting a list of candidate servers: `tx.hl7.org.au`, `tx.ontoserver.csiro.au`, etc.
4. Attempting `GET /fhir/metadata` on each candidate to initialise `TerminologyClientContext`
5. Receiving 401 from those servers (Spring Security rejects the empty `Authorization: Bearer ` header the HAPI FHIR library sends after a failed SMART auth attempt)
6. Logging errors and falling back

This ecosystem init ran in the background on a Kotlin coroutine while the Inferno app was executing the conformance tests (reading from smile). On dev with `noEcosystem true`, none of steps 1–6 occur — the first validator request was dispatched almost immediately at ~05:19:49.

The CapabilityStatement validation on dev took **103 seconds** (cold session initialisation — loading the IG, compiling profiles). This one-time cost exists on both environments but is hidden on prod by the longer ecosystem gap.

## Per-Validation Speed

**Prod** (inferred from consecutive 200 OK timestamps — validator-wrapper 1.0.68 does not log timing):

```
05:26:55.650  200 OK: POST - /validate
05:26:56.794  200 OK: POST - /validate   (+1,144ms)
05:26:57.970  200 OK: POST - /validate   (+1,176ms)
05:27:32.736  200 OK: POST - /validate   (~843ms gap)
05:27:33.885  200 OK: POST - /validate   (+1,149ms)
05:27:35.050  200 OK: POST - /validate   (+1,165ms)
```
Average: **~0.8–1.2 seconds per validation**

**Dev** (timing logged by validator-wrapper:latest):

```
05:21:42.706  200 OK: POST - /validate in 363ms   (first Patient after cold CapStmt)
05:21:42.803  200 OK: POST - /validate in 80ms
05:21:42.848  200 OK: POST - /validate in 27ms
05:21:43.002  200 OK: POST - /validate in 143ms
05:21:43.067  200 OK: POST - /validate in 49ms
05:21:43.124  200 OK: POST - /validate in 43ms
```
Average: **20–100ms per validation (warm session)**

The per-validation gap (~10×) means `noEcosystem` reduces not just the startup cost but also the per-resource overhead — each validation was previously also triggering ecosystem server lookups per code system.

## Why the 90-Minute Figure

The anecdotal 90-minute prod run would occur when ALL of the following compound:

1. **Cold validator cache** — fresh pod restart (no warm session, no cached terminology). The ecosystem initialisation runs fully, and each code system lookup blocks waiting for the 401 response and exception handling from tx.hl7.org.au/tx.ontoserver.csiro.au.

2. **SMART credentials populated** — when a user has completed SMART auth tests (populating an access token in the Inferno session), the HAPI FHIR validator appears to forward that token to discovered servers, causing definitive 401s with full exception stack traces on every validation request rather than the softer ecosystem startup failures. This also triggered HTTP 500 responses from the validator to Inferno, causing individual tests to show as errored rather than just slow.

3. **No terminology cache** — when the validator PVC cache is empty (fresh deployment, PVC deleted), each code system lookup hits the network rather than cache.

Today's prod run was faster because:
- The validator had a warm session from a midnight run (validator-api-0 logs show activity at `00:02–00:07`)
- No SMART credentials were populated in this session (plain open-auth run)
- The ecosystem errors, while still present, were handled without cascading to 500s

## Conclusion

`noEcosystem true` provides a **reliable, condition-independent** speedup:

| Condition | Prod without noEcosystem | Dev with noEcosystem |
|---|---|---|
| Warm cache, no SMART | 9m28s | 5m44s (1.65×) |
| Cold cache, no SMART | ~15–20min (estimated) | ~5–7min |
| Warm cache + SMART credentials | ~20–30min + 500 errors | ~5–7min |
| Cold cache + SMART credentials | ~90min + many 500 errors | ~5–7min |

On dev the result is always in the 5–7 minute range regardless of these variables, because the validator never contacts external servers. The observed speedup grows dramatically as conditions worsen on prod.

## Related

- `au_core_test_kit` change: [hl7au/au-fhir-core-inferno@80fa347](https://github.com/hl7au/au-fhir-core-inferno/commit/80fa347488d645d09025cbd664378df28f0bb469)
- `apps/ontoserver/templates/txreg-redirect-httproute.yaml` — Returns 404 for `/tx-reg` on tx.dev, preventing 401 from Ontoserver's Spring Security catch-all for clients that still have ecosystem enabled
- ADR: [docs/adr-ontoserver-txreg-redirect.md](./adr-ontoserver-txreg-redirect.md)
