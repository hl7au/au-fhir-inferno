# Validator Configuration & Optimisation

Documents all configuration decisions made to the HAPI FHIR validator-wrapper deployment, why they were made, and what effect they had. Changes are listed chronologically.

## Current Architecture

The validator runs as a **StatefulSet** (2 replicas in prod, 1 in dev), each pod with its own persistent volumes for package and terminology caches. A Kubernetes Service with `sessionAffinity: ClientIP` ensures each Inferno pod always hits the same validator pod.

---

## Changes

### 1. Deployment → StatefulSet (with persistent caches)

**Why:** Each validator pod caches downloaded FHIR packages and terminology validation results to disk. Without persistence, every pod restart re-downloaded all packages (~2–3 minutes per restart). With a Deployment, PVCs cannot be bound per-replica, so all pods would have to share one cache or start cold.

**What changed:**
- Converted from `Deployment` to `StatefulSet`
- Added two `volumeClaimTemplates` per pod:

| Cache | Mount | Size | Purpose |
|---|---|---|---|
| `fhir-package-cache` | `/home/ktor/.fhir/packages` | 5Gi | Downloaded IG packages (hl7.fhir.au.core, etc.) |
| `terminology-cache` | `/tmp/default-tx-cache` | 2Gi | Terminology validation results from tx.dev |

Both mounts use `subPath:` to avoid EXT4 `lost+found` causing initialisation errors on fresh volumes.

**Result:** Pod restarts go from ~2–3 minutes (re-downloading packages) to ~10–15 seconds (JVM start only).

**Note on cache invalidation:** The terminology cache persists across pod restarts. If the tx server configuration changes (e.g. SMART-on-FHIR advertised/removed), the cache must be manually cleared before restarting:
```bash
kubectl exec -n <namespace> validator-api-0 -- find /tmp/default-tx-cache -type f -delete
kubectl exec -n <namespace> validator-api-1 -- find /tmp/default-tx-cache -type f -delete
kubectl rollout restart statefulset/validator-api -n <namespace>
```

---

### 2. CPU resource increase (4×)

**Why:** Under the original `250m` CPU request / `500m` limit, the validator pod ran at load average 3.00 against 0.5 available CPU — severe throttling. Package downloads and validation both stalled.

**What changed:**
- CPU request: `250m` → `1000m`
- CPU limit: `500m` → `2000m`
- Memory adjusted separately to right-size heap allocation

**Result:** First startup dropped from ~2–3 minutes to ~30–60 seconds. Ongoing validation throughput increased significantly.

---

### 3. Health probes tuned

**Why:** The default probe timings were too aggressive for a JVM app that downloads FHIR packages on first start. Pods were being killed and restarted before they were ready.

**What changed:**

| Probe | Key setting | Value | Reason |
|---|---|---|---|
| Startup | `failureThreshold: 30`, `periodSeconds: 10` | Up to 5 min | Allows initial package downloads |
| Readiness | `failureThreshold: 6`, `periodSeconds: 5` | 30s budget | Prevents premature traffic routing |
| Liveness | `failureThreshold: 5`, `periodSeconds: 30` | 2.5 min budget | Allows brief hangs during preset loading |

---

### 4. Session affinity: ClientIP

**Why:** With 2 validator replicas and a standard round-robin Service, requests from the same Inferno session were distributed across both pods. The validator-wrapper caches validation sessions in memory (`SESSION_CACHE_DURATION: -1` = never expire). A session created on `validator-api-0` would not be found on `validator-api-1`, causing the validator to spin up a new session on every other request — discarding the cache benefit entirely and reloading IG packages each time.

**What changed** (`infra/helm/inferno/templates/services/validator-api.service.yaml`):
```yaml
spec:
  sessionAffinity: ClientIP
  sessionAffinityConfig:
    clientIP:
      timeoutSeconds: 3600   # 1 hour
```

**How it works:** Kubernetes hashes the client IP (the Inferno app or worker pod IP) and routes all requests from that IP to the same validator pod. The 1-hour timeout matches the typical duration of a full AU Core test suite run.

**Result:** Session cache hits on every validation request after the first. Without this, each validation call that landed on the "wrong" pod would create a new session — loading the IG from scratch and adding ~1–2 minutes per cold start.

---

### 5. noEcosystem: true (au_core_test_kit 1.4.1)

**Why:** The HAPI FHIR validator's ecosystem feature queries a terminology registry (tx-reg) to discover external servers for code validation, then attempts to connect to those servers. When the validator used `tx.dev.hl7.org.au` (an Ontoserver with SMART-on-FHIR advertised in its capability statement), it attempted SMART authentication, stored an empty token on failure, then forwarded that empty `Authorization: Bearer ` header to all discovered servers (`tx.hl7.org.au`, `tx.ontoserver.csiro.au`). Both Ontoserver instances reject malformed tokens with 401 even on public paths, due to Spring Security validating the token before `permitAll()` rules apply.

This caused:
- An ~8-minute startup delay before any resource validation (ecosystem initialisation)
- ~1-second per-validation overhead (ecosystem server lookup on each code)
- Intermittent HTTP 500 errors from the validator when SMART credentials were populated

**What changed** (`au_core_test_kit` 1.4.0 → 1.4.1, commit `80fa347`):
```ruby
cli_context do
  txServer ENV.fetch('TX_SERVER_URL', 'https://tx.dev.hl7.org.au/fhir')
  disableDefaultResourceFetcher false
  noEcosystem true   # ← added
end
```

Applied to all three suites: `v1.0.0`, `v2.0.0`, and `validation_suite`.

**Result:** AU Core v1.0.0 test suite runtime reduced from 9m28s (prod, ecosystem enabled) to 5m44s (dev, noEcosystem). Under worst-case conditions (cold cache + SMART credentials populated) the improvement is much larger — previously ~90 minutes with cascading 500 errors.

**Trade-off:** The validator uses only `tx.dev.hl7.org.au` for all code validation — no federation to `tx.hl7.org.au` or `tx.ontoserver.csiro.au`. As long as tx.dev has the required AU IG content (which it does via AHTS and AEHRC syndication), this is safe.

See [docs/noecosystem-performance-analysis.md](docs/noecosystem-performance-analysis.md) for the full timing comparison.

---

### 6. Presets: pre-warm IG package cache on startup

**Why:** The validator downloads IG dependency packages during the first session creation after a pod starts. On a fresh PVC (rolling update, new pod), this means ~1–2 minutes of package downloads before the first user validation completes. Presets trigger session creation during the startup window — before the readiness probe passes — so users never see the cold-start cost.

**What changed:**
- Added `infra/helm/inferno/templates/configs/validator-presets-configmap.yaml` — a ConfigMap containing a `presets.json` that pre-creates sessions for each supported IG version
- Mounted the ConfigMap into the validator pod at `/presets/`
- Set `VALIDATION_SERVICE_PRESETS_FILE_PATH=/presets/presets.json` env var

**IGs pre-warmed** (derived from observed session logs):

| Preset | IG |
|---|---|
| `au-core-v1.0.0` | `hl7.fhir.au.core#1.0.0` |
| `au-core-v2.0.0` | `hl7.fhir.au.core#2.0.0` |
| `au-ps-v1.0.0-preview` | `hl7.fhir.au.ps#1.0.0-preview` |
| `smart-app-launch-v2.2.0` | `hl7.fhir.uv.smart-app-launch#2.2.0` |

Each preset includes `noEcosystem: true` and the `txServer` value from `inferno.terminologyServer` (templated via Helm), ensuring the pre-warmed session matches what Inferno will request at runtime. Transitive dependency packages (~83 total, ~4.5GB) are downloaded automatically as part of the preset session initialisation.

**Why ConfigMap over baking packages into the Docker image:**
- The prod package cache is 4.5GB — embedding it would make image push/pull impractical
- ConfigMap keeps IG version management in the same IaC repo as deployment config, updated without a Docker build
- Packages persist in the PVC after first startup, so subsequent restarts are instant regardless

**Measured improvement (warm PVC):**

The presets pre-load parsed resources into JVM heap. When Inferno's user session then initialises for the same IGs, the JVM reuses the already-parsed packages rather than re-reading them from disk. Loading 4,000+ resources per terminology package from disk takes significant time even on a local SSD.

| Scenario | Cold session init (CapabilityStatement) |
|---|---|
| Before presets (warm PVC) | **103s** |
| After presets (warm PVC) | **32s** (3× improvement) |

Subsequent validations in the same session remain fast (20–100ms) in both cases — the gain is specifically in first-session initialisation.

**Fresh PVC benefit (rolling updates):** Without presets, the first user after a pod replacement waits for network package downloads (~1–2 min). With presets, downloads happen during the startup window before the readiness probe passes — users never see them.

**Updating presets when IG versions change:** Edit `validator-presets-configmap.yaml` and roll the StatefulSet. The new pod downloads the new packages during its startup window.

**How the JVM warming and `baseEngine` work (source-verified from validator-wrapper):**

When the validator loads an IG package (e.g. `hl7.terminology.r4#7.1.0` — 4,000+ resources), it reads each resource file from disk and parses it into a Java object in the JVM heap. This takes 10–17 seconds per large package. The parsed objects stay in heap for the lifetime of that session.

The validator-wrapper holds a `ConcurrentHashMap<String, ValidationEngine>` called `baseEngines` — one fully-built engine per preset key, loaded at startup. These engines sit in JVM heap indefinitely.

When a validation request arrives specifying `baseEngine: "AU_CORE_V2_0_0"`:
1. The validator finds the pre-built engine in the `baseEngines` map
2. Calls the **copy constructor**: `new ValidationEngine(existingEngine)`
3. This does a **shallow reference copy** — the 4,000+ parsed resource objects are shared by reference, not re-read from disk
4. The new session is ready in seconds rather than 10–17 seconds per package

Without `baseEngine` in the request, every new session triggers a full disk parse — each package re-read and re-parsed from the PVC cache at 10–17 seconds each.

**Critical rule: `baseEngine` key must match the exact IG version the suite validates against.** The base engine contains fully-loaded StructureDefinitions (profiles, extensions, etc.) for a specific IG version. FHIR resources are keyed by canonical URL, not by URL+version. If the base engine has `au.core#2.0.0` and the session then loads `au.core#1.0.0-ballot`, both versions' profiles are in the same context under the same canonical URLs — the validator cannot reliably determine which version to use. Each suite's `baseEngine` key must correspond to its `igs` declaration:

| Suite | `igs` | `baseEngine` |
|---|---|---|
| au_core v1.0.0 | `hl7.fhir.au.core#1.0.0` | `AU_CORE_V1_0_0` |
| au_core v2.0.0 | `hl7.fhir.au.core#2.0.0` | `AU_CORE_V2_0_0` |
| validation_suite | `hl7.fhir.au.core#1.0.0-ballot` | `AU_CORE_V1_0_0_BALLOT` |
| au_ps | `hl7.fhir.au.ps#1.0.0-preview` | `AU_PS_V1_0_0_PREVIEW` |

**`au_core_test_kit` 1.4.3** adds `baseEngine` to each suite's `cli_context` with the matching key.

**Session cache internals:**
- Cache holds up to **4 sessions** (hardcoded in `GuavaSessionCacheAdapter`, no config knob)
- With `SESSION_CACHE_DURATION: -1` sessions don't expire by time, but LRU eviction at 4 entries applies
- Without `baseEngine`: eviction triggers a 10–17s full disk rebuild
- With `baseEngine`: eviction triggers a fast in-memory copy — the 4-entry limit is no longer a concern

**The `VALIDATION_SERVICE_ENGINE_RELOAD_THRESHOLD` setting (default 250MB):** When free JVM heap drops below this value, the validator recreates the engine. Can cause unexpected slow rebuilds if multiple sessions are initialising large packages simultaneously during startup.

**Are the 10–17s loads repeated across multiple runs?**

No. Once a session is cached and Inferno reuses the same `sessionId`, every subsequent request hits `"Cached session exists"` with zero cost. The slow loads only occur at:
1. **First startup** — preset loading builds each base engine once from disk; `InvokeValidatorSession` per suite creates the Inferno-side session (fast copy via `baseEngine`)
2. **Pod restart** — session cache is in-memory and lost; presets re-warm the base engines during the startup window before the readiness probe passes
3. **Session eviction** (>4 concurrent active sessions) — fast with `baseEngine`, slow without

---

### 7. tx-reg HTTPRoute (404 direct response)

**Why:** Even with `noEcosystem true`, the HAPI FHIR validator still calls `/tx-reg/resolve` on the configured tx server in some code paths. Ontoserver does not implement the tx-reg protocol — the path fell through to Spring Security's `.anyRequest().authenticated()` catch-all and returned 401. A 404 is the semantically correct response ("not implemented here") and is handled more gracefully by the validator than 401.

**What changed** (`sparked-argo/apps/ontoserver/templates/txreg-redirect-httproute.yaml`):

An Envoy Gateway `HTTPRouteFilter` + `HTTPRoute` intercepts requests to `/tx-reg/*` on `tx.dev.hl7.org.au` and returns a direct 404 before the request reaches Ontoserver.

See [sparked-argo/docs/adr-ontoserver-txreg-redirect.md](https://github.com/hl7au/sparked-argo/blob/main/docs/adr-ontoserver-txreg-redirect.md) for the full decision record including the earlier redirect-to-tx.fhir.org approach that was tried and why it was abandoned.

---

## Managing PVCs

StatefulSet PVCs persist after pod deletion and must be removed manually if a full reset is needed:

```bash
kubectl delete pvc -n <namespace> -l app=validator-api
```

Deleting PVCs forces re-download of all packages on next startup (~30–60 seconds with current CPU allocation).

## Related Docs

- [docs/performance-feature.md](docs/performance-feature.md) — per-session performance tracking (FHIR + validator timing)
- [docs/noecosystem-performance-analysis.md](docs/noecosystem-performance-analysis.md) — prod vs dev timing comparison
- [sparked-argo/docs/adr-ontoserver-txreg-redirect.md](https://github.com/hl7au/sparked-argo/blob/main/docs/adr-ontoserver-txreg-redirect.md) — tx-reg decision record
