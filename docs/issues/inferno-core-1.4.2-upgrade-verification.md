# inferno_core 1.0.8 to 1.4.2: upgrade verification

Record of the before/after evidence behind #162 and the inferno_core 1.4.2 bump. Written
so the next person does not have to re-run six hours of suites to know what was checked,
what was found, and what was deliberately left unverified.

## Result

906 tests compared across four suites. **Zero result changes.**

| suite | tests | result changes | comparison |
|---|---|---|---|
| AU Core v1.0.0 | 394 | 0 | controlled: same kits, only `inferno_core` varies |
| AU Core v2.0.0 | 425 | 0 | controlled |
| AU PS 1.0.0 (3 bundles) | 87 | 0 | uncontrolled, see caveat |
| AU Core v3.0.0-ballot1 | 498 | not verified | see "Not verified" |

Message text is byte-identical too on both AU Core suites, once per-run server-generated
UUIDs are normalised: 0 of 819 tests differ in a single validation message.

## Why this is a controlled comparison

The two AU Core legs differ in exactly one input. Both run:

- `au_core_test_kit` at the same commit (1.4.5 plus the reference-resolution fix)
- `inferno_suite_generator` at `da378cb`
- `au_ps_inferno` at 1.0.0 plus the gemspec relaxation
- the same validator-wrapper container, `1.0.68`, held constant
- the same server, `https://fhir.hl7.org.au/aucore/fhir/DEFAULT`
- the same suite-declared default inputs, recorded in the results file and asserted equal
  by the diff tool

That is possible because both test-kit fixes are written against DSL that exists in
1.0.6 as well, so the patched kits run unchanged on either inferno_core line. Holding the
kits fixed and varying only `inferno_core` is what makes "no change" attributable.

## What the two changed code paths are

The upgrade's whole runtime risk is that inferno_core v1.1.0 removed three `Validator`
methods the AU kits called to validate a reference target without logging its messages.
Two separate modules did this, and the suites split across them:

| suite | reference-resolution tests | module |
|---|---|---|
| AU Core v1.0.0 | 18 | `AUCoreTestKit::ReferenceResolutionTest` |
| AU Core v2.0.0 | 20 | `InfernoSuiteGenerator::ReferenceResolutionTest` |
| AU Core v2.1.0-draft | 24 | generator |
| AU Core v3.0.0-ballot1 | 24 | generator |
| AU PS 1.0.0 | 0 | n/a |

v1.0.0 and v2.0.0 therefore cover **both** rewritten modules, which is why they were the
two suites worth spending the time on.

## AU PS caveat

The AU PS numbers compare the local 1.0.8 leg against the **preview environment** on
1.4.2, not against the local 1.4.2 leg. The local 1.4.2 leg could not complete AU PS:
in a 7 GB Docker VM the validator rebuilt its engine on every run and timed out on the
bundle-validation test, in every attempt. The preview environment has adequate resources
and completed the same bundles in 11 to 118 seconds.

All 87 tests match. But the preview runs `validator-wrapper:1.0.78` where the local legs
run `1.0.68`, so this pair is **not** controlled. The message-level diff shows exactly
that: the only test with differing messages is the bundle validation, and the differences
are terminology behaviour between validator core 6.6.3 and 6.9.7 (a SNOMED code moving
between `Unknown code` phrasings and value-set membership notes). The messages name their
own versions, which is what makes the attribution safe. Results are unaffected.

Since dev and prod both run `1.0.78`, the preview pairing is arguably closer to production
than the local one. It is still corroboration rather than the controlled experiment.

## Not verified

**AU Core v3.0.0-ballot1** was dropped. The local environment could not sustain a
498-test suite: the validator went unreachable mid-run and produced 47 infrastructure-
caused non-passes. Re-running it group by group was under way and would have taken about
four more hours.

The call to drop it was deliberate. v3.0.0-ballot1 was released too recently for anyone
to have exercised it, and it uses the same `InfernoSuiteGenerator::ReferenceResolutionTest`
module that v2.0.0 already verified clean. It would have been a third data point on an
already-verified module, not new coverage.

**Puma 5 to 8 under concurrency** is not covered here. Re-run the probe in
`docs/issues/inferno-app-tier-concurrency-504.md` against the preview before prod moves,
since #159 tuned the database pool against Puma 5's threading.

## Baseline shape, for future re-baselining

Non-passes on the AU Core suites are server-side findings on the reference server, not kit
problems, and they are identical on both legs:

- v1.0.0: 384 pass, 7 fail, 3 skip. Failures are gender-identity search returning 400,
  PractitionerRole chaining finding no references, and one CapabilityStatement conformance
  gap.
- v2.0.0: 414 pass, 5 fail, 6 skip.
- AU PS: 24/24 on the mandatory bundle; the optional and unresolved-reference fixtures
  fail 4 and 5 tests respectively, by design.

## Environment notes worth knowing before repeating this

Three things cost hours and are worth not rediscovering:

1. **The validator wants more than 7 GB.** `SESSION_CACHE_DURATION: -1` keeps one
   validation engine per suite forever; four AU Core IG versions plus AU PS grew it to
   6.5 GB inside a 7 GB VM. Starvation surfaced as Docker DNS failures (`getaddrinfo`) in
   the worker and read timeouts against the validator, never as an OOM kill, so it looked
   like network trouble. Give Docker 16 GB or more before attempting the full set.
2. **The wrapper has no health endpoint.** `/version`, `/igs` and `/validate` all 404 on
   GET. A probe that waits for a response body never succeeds; a probe that accepts any
   HTTP status returns long before the validation engine has loaded its terminology. The
   only reliable readiness signal is a validation that actually succeeds.
3. **Always cancel a run you stop waiting for.** An abandoned run keeps executing and
   contends with whatever starts next, which silently corrupts both.

Any run whose failures carry DNS, connection or validator-timeout signatures is discarded
rather than reported. Those signatures are enumerated in the harness so a degraded
environment cannot quietly become evidence.

## Second pass: released gems, inferno_core 1.4.3, generator bump

The run above compared inferno_core 1.0.8 against 1.4.2 with the test kits pinned to
branches. What prod actually adopts differs from that in four ways, so the preview was
re-verified after the gems were released.

| variable | first pass | what prod adopts |
|---|---|---|
| `inferno_core` | 1.4.2 | **1.4.3** |
| `au_core_test_kit` | commit `7b14fa2f` | **1.4.6** |
| `au_ps_inferno` | commit `908f2d96` | **1.0.1** |
| `inferno_suite_generator` | `da378cb` on both legs | **`9b0d17e` to `da378cb`** |

`au_core_test_kit` 1.4.6 needed no re-run: unpacking the released gem and diffing it
against `7b14fa2f` shows the only differences are `version.rb` and files the gemspec never
packages (`summary.md`, generator templates and assets). It is the verified commit.

### The generator bump is forced, not optional

Earlier notes recorded moving prod from `9b0d17e` to `da378cb` as a separate change. It is
not separable. At `9b0d17e`, `test_modules/reference_resolution_test.rb` still calls
`operation_outcome_from_hl7_wrapped_response`, `message_hash_from_issue` and
`filter_messages`, all removed in inferno_core v1.1.0. Prod cannot run 1.4.x on that ref.

### Method

Prod is the correct baseline, not dev. Prod and the preview both run
`validator-wrapper 1.0.78` / validator core 6.9.7, so the pairing is controlled on the
validator. Dev tracks the newest wrapper (1.0.84 / core 6.10.3) by design, which makes it
useless as a baseline here: on dev the AU PS bundle-validation tests fail where prod passes,
and that difference is the validator version, not the kit.

### Results, preview against prod

| check | prod | preview | changed |
|---|---|---|---|
| AU Core v1.0.0 Encounter group (20 tests) | 16 pass, 4 fail | 16 pass, 4 fail | none |
| AU Core v2.0.0 Encounter group (20 tests) | 16 pass, 4 fail | 16 pass, 4 fail | none |
| AU PS mandatory bundle (29 shared tests) | 25 pass, 4 skip | 25 pass, 4 skip | none |
| AU PS, new test in 1.0.1 | n/a | `nilknown_warning` passes | +1 test |

The Encounter groups were chosen because they cover **both** reference-resolution modules:
v1.0.0 uses `AUCoreTestKit::ReferenceResolutionTest` (the au_core_test_kit copy), v2.0.0
uses `InfernoSuiteGenerator::ReferenceResolutionTest` (the generator copy, the one the
forced ref bump replaces). Both `reference_resolution_test` cases pass on the preview.

The four Encounter failures are `patient_chain`, `patient_ihi_chain`, `patient_dva_chain`
and `patient_medicare_chain`, all "There is no reference to the target resource in the
returned result". They are identical on prod, dev and the preview: server-side findings on
the reference server, not a kit regression.

### Session creation, after deleting HoistChildrenAvailableInputs

The local patch is gone and the upstream hoist carries it. Measured on the preview:

| suite | tests | session creation |
|---|---|---|
| au_ps_v100 | 87 | 0.38s |
| au_core_v100 | 394 | 0.78s |
| au_core_v200 | 425 | 0.87s |
| au_core_v210_draft | 498 | 0.87s |
| au_core_v300_ballot1 | 498 | 0.72s |

Comfortably inside the 15s Envoy route timeout, against the 4.93s that
`au_core_v210_draft` cost on 1.0.8 with the patch removed. The 504 risk #159 addressed does
not reopen.

### AU PS message improvement is real

Same validator, same bundle, `au_ps_inferno` 1.0.0 against 1.0.1:

| | prod (1.0.0) | preview (1.0.1) |
|---|---|---|
| warnings | 67 | 18 |
| information | 47 | 32 |
| "CodeSystem 'http://snomed.info/sct' version 'null' could not be found" | 37 | 0 |

That is #108 (`snomedCT 'au'`) working end to end, with no result changes.

## Follow-up found by this pass: AU Core still asks for the International edition

The generator's configurable SNOMED edition (`3edfd8f`) ships in `da378cb`, and its default
is the International edition. On the preview the AU Core SNOMED warnings change from

    version 'null' could not be found

to

    version 'http://snomed.info/sct/900000000000207008' could not be found

`900000000000207008` is the SNOMED CT core (International) module. The AU terminology server
carries the Australian edition, `32506021000036107`, so the codes still go unvalidated: 56 of
them in the v2.0.0 Encounter group alone. Results are unchanged and prod has the same
unvalidated codes today under the older wording, so this does not block the upgrade.

The fix is the one AU PS already took in hl7au/au-ps-inferno#108: set the generator's
`snomed_edition` to `au` for the AU Core suites. Worth raising separately.
