# Upstream brief: `CanonicalResourceManager.copy()` is an incomplete clone

**Status:** investigated, not yet reported upstream. Prepared as a self-contained brief so
an upstream issue/PR can be raised without re-deriving any of it.

**Repo:** [`hapifhir/org.hl7.fhir.core`](https://github.com/hapifhir/org.hl7.fhir.core)
**File:** `org.hl7.fhir.r5/src/main/java/org/hl7/fhir/r5/context/CanonicalResourceManager.java`
**Verified at:** tags `6.9.7` and `6.9.12` (identical), 2026-07-25
**Our exposure:** [`VALIDATOR_OPTIMIZATION.md` §9](../../VALIDATOR_OPTIMIZATION.md) — worked around locally by shipping an empty `presets.json`

> Raise this upstream only with the verification in "Before filing" done. The repo has a
> high scrutiny bar and this brief deliberately stops short of claims that are inferred
> rather than proven. Everything below marked **VERIFIED** was read from source at the
> stated tag; everything marked **INFERRED** has not been reproduced in a test.

---

## 1. The defect

`CanonicalResourceManager` maintains **six** collections. `copy()` populates **three**.

```java
// CanonicalResourceManager.java:301-309 @ 6.9.12
public void copy(CanonicalResourceManager<T> source) {
  allResources.clear();
  indexedResources.clear();
  allResources.addAll(source.allResources);
  indexedResources.putAll(source.indexedResources);
  for (Map.Entry<String, List<CachedCanonicalResource<T>>> entry : source.listForUrl.entrySet()) {
    listForUrl.put(entry.getKey(), new ArrayList<>(entry.getValue()));
  }
}
```

| Field | decl. | populated by `see()` | copied by `copy()` |
|---|---|---|---|
| `allResources` | `:269` | ✓ `:393` | ✓ |
| `listForId` | `:270` | ✓ `:387-391` | **✗** |
| `listForUrl` | `:271` | ✓ `:401` | ✓ *(added 6.9.7, [#2327](https://github.com/hapifhir/org.hl7.fhir.core/pull/2327))* |
| `masterDefinitions` | `:272` | ✓ `:399` | **✗** |
| `indexedResources` | `:273` | ✓ | ✓ |
| `supplements` | `:274` | ✓ `:405` (`addToSupplements`) | **✗** |

**VERIFIED.** `copy()` at `6.9.12` is byte-identical to `6.9.7`; #2327 fixed only `listForUrl`.

Also not copied: the `enforceUniqueId` and `minimalMemory` configuration flags (`:267-268`),
and `loadCount` (`:29`). `enforceUniqueId` gates the `listForId` write at `:386`, so a clone
whose flag defaults differently from its source would diverge further.

## 2. Why `copy()` is the right place to fix it

`CanonicalResourceManager.copy()` has exactly **one** call site, and it is a clone
constructor chain with no post-copy index rebuild:

```
ValidationEngine(ValidationEngine other)                    org.hl7.fhir.validation
  └─ new SimpleWorkerContext(other)                         SimpleWorkerContext.java:213
       └─ copy(other)                                                             :223
            └─ super.copy(other)  = BaseWorkerContext.copy()  BaseWorkerContext.java:354
                 └─ .copy() on 14 CanonicalResourceManager instances          :357-379
                    (codeSystems, valueSets, maps, transforms, structures,
                     searchParameters, plans, questionnaires, operations,
                     systems, guides, capstmts, measures, libraries)
```

**VERIFIED.** `BaseWorkerContext.copy()` otherwise copies ~30 fields explicitly and does not
reindex afterwards, so the method's only contract is "produce an equivalent manager". This is
a core defect; it is not caused by, and cannot be fixed in, any downstream wrapper.

## 3. Observable consequence

The clearest path is `masterDefinitions`, consulted **first** on bare-URL resolution:

```java
// CanonicalResourceManager.java:713-719
public T get(String url) {
  CachedCanonicalResource<T> cr = masterDefinitions.get(url);   // empty in a clone
  if (cr != null) return cr.getResource();
  return indexedResources.containsKey(url) ? indexedResources.get(url).getResource() : null;
}
```

`see()` at `:396-401` puts a resource into `masterDefinitions` when its package
`isMaster()` and it is a `CodeSystem`/`ValueSet`, or a `StructureDefinition` with
derivation `specializes`, excluding `http://terminology.hl7.org`. That map therefore
encodes **master-package precedence for a bare canonical URL**.

In a clone the map is empty, so `get(url)` silently skips that precedence and returns
whatever `indexedResources` holds. **INFERRED:** with two versions of one IG co-resident
(our case: AU Core 1.0.0 and 2.0.0), this flips which version wins for a versionless
canonical. That is consistent with the symptom in §9 — the failure moved from v1.0.0 to
v2.0.0 after a wrapper bump, i.e. a co-residency defect rather than a version-specific one —
but we have **not** reproduced it in an isolated test.

`getByPackage(String url, List<String> pvlist)` at `:781` consults `masterDefinitions` the
same way.

`listForId` and `supplements` are similarly consulted at `:654` and `:886`/`:896`.

## 4. Adjacent, already-tracked bug (do not conflate)

`:615` `while (listForId.values().remove(cr));` carries an in-source `FIXME`: SpotBugs
`GC_UNRELATED_TYPES`, always false because `values()` is `Collection<List<...>>`, not
`Collection<CachedCanonicalResource<T>>`. So `drop()` never removes from `listForId`.
Tracked upstream as open issue
[#2484](https://github.com/hapifhir/org.hl7.fhir.core/issues/2484) ("FIXME: SpotBugs
GC_UNRELATED_TYPES"). **This is a different bug.** Keep them separate in any report.

## 5. Prior art search

Searched `repo:hapifhir/org.hl7.fhir.core` issues and PRs for `CanonicalResourceManager`
(2026-07-25). Related but distinct: #2484 (SpotBugs FIXME, open), #2331 (cache `getList`,
closed), #2322 (O(1) `drop`, closed), #2166 (concurrency, closed), #2327 (the partial
`listForUrl` fix, merged). **Nothing covers the incomplete `copy()`.**

## 6. Candidate fix

```java
public void copy(CanonicalResourceManager<T> source) {
  allResources.clear();
  indexedResources.clear();
  listForId.clear();
  listForUrl.clear();
  masterDefinitions.clear();
  supplements.clear();

  allResources.addAll(source.allResources);
  indexedResources.putAll(source.indexedResources);
  masterDefinitions.putAll(source.masterDefinitions);
  for (Map.Entry<String, List<CachedCanonicalResource<T>>> e : source.listForUrl.entrySet())
    listForUrl.put(e.getKey(), new ArrayList<>(e.getValue()));
  for (Map.Entry<String, List<CachedCanonicalResource<T>>> e : source.listForId.entrySet())
    listForId.put(e.getKey(), new ArrayList<>(e.getValue()));
  for (Map.Entry<String, List<CachedCanonicalResource<T>>> e : source.supplements.entrySet())
    supplements.put(e.getKey(), new ArrayList<>(e.getValue()));
}
```

Note the existing method does not `clear()` `listForUrl` before writing into it; the added
`clear()` calls make the copy total rather than additive. Whether `enforceUniqueId` /
`minimalMemory` should also be carried over is a **question for the maintainers**, not
something to assert — changing them alters `see()` behaviour on the clone.

## 7. Before filing

1. **Reproduce in a unit test in-repo.** Build a manager via `see()` with two versions of one
   canonical from different packages (one master), `copy()` it, and assert `get(url)` returns
   the same resource from both. This is the single most important missing piece — everything
   in §3 beyond the source reading is inference.
2. **Check `main`**, not just `6.9.12`; it may have moved.
3. **Decide the `enforceUniqueId` / `minimalMemory` question** or explicitly leave it to
   maintainers in the issue text.
4. **Do not bundle #2484.** File the `copy()` gap on its own.
5. Frame it as extending #2327 (same author's fix, same method, remaining fields) rather than
   as a new discovery — that is accurate and lowers review friction.

## 8. What this means for us either way

Our workaround (empty `presets.json`, §9) removes the clone path entirely and costs a
~35-50s fresh build for the first session per suite after a restart, which the warmer sidecar
absorbs. §8 separately measured that `baseEngine` cloning gave **no** speedup on 6.6.3/6.9.7
anyway, so even a fixed `copy()` is not on its own a reason to re-enable presets. Re-enabling
should be driven by a measured win, not by the bug being closed.
