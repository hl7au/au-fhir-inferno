# Which SNOMED CT edition the validator uses, and what tx.dev must carry

**Status:** root-caused and measured here.
**Effect:** with the wrong edition selected, ~20 spurious warnings and ~10 spurious
information messages per AU PS bundle, plus an intermittent spurious `error`.
**Action taken:** test kits now select the **Australian** edition
(`cliContext.snomedCT`); `tx.dev.hl7.org.au` continues to carry the Australian edition
**only**.

> Read this before loading SNOMED CT International onto `tx.dev.hl7.org.au`. Carrying the
> Australian edition alone is a deliberate decision, not an omission.

---

## 1. How the validator picks an edition

`cliContext.snomedCT` defaults to the International edition,
`900000000000207008` (`ValidationContext.java` in `org.hl7.fhir.core`).
`ValidationEngine.setSnomedExtension` converts it into an expansion parameter sent with
every terminology request:

```
system-version = http://snomed.info/sct|http://snomed.info/sct/900000000000207008
```

This is visible in the validator's own on-disk cache. From a live pod's
`/tmp/default-tx-cache/all-systems.cache`:

```json
{
  "name": "system-version",
  "valueCanonical": "http://snomed.info/sct|http://snomed.info/sct/900000000000207008"
}
```

`tx.dev.hl7.org.au` carries only the Australian edition, so that parameter matches
nothing and every SNOMED lookup fails:

```
A definition for CodeSystem 'http://snomed.info/sct' version 'null' could not be found,
so the code cannot be validated. Valid versions: [http://snomed.info/sct/32506021000036107/version/...]
```

The validator then reports valid codes as absent from their value sets. This is the
damaging part: the failure does not present as a configuration error, it presents as
content warnings against the resource under test, which reads to an implementer as a
problem with their data.

Every flagged code checks out when the terminology server is queried directly:

| Code | Value set | `$validate-code` |
|---|---|---|
| `782415009`, `1269424006`, `373568007` | indicator-hypersensitivity-intolerance-to-substance-2 | true |
| `160245001` | clinical-condition-1 | true |
| `288565001` | healthcare-organisation-role-type-1 | true |
| `62247001` | practitioner-role-1 | true |
| `89811004`, `21522001`, `84229001`, `247472004` | adverse-reaction-* | true |
| `446141000124107` | gender-identity-response-1 (target of `inv-pat-1`) | true |
| `23281011000036106` | australian-medication-1 | true |

## 2. Why the Australian edition is the right selection

**It is a superset, not an alternative.** The Australian edition is a derivative that
contains the full International release plus the AU extension and AMT. Selecting it
loses no International content, so there is no category of concept that International
would resolve and Australian would not.

**AMT exists nowhere else.** `23281011000036106` (Bisoprolol fumarate 2.5 mg tablet)
carries `moduleId` `32506021000036107`. AU Core puts a **required** binding on
`Medication.code.coding:amt` → `australian-medication-1`. Only the Australian edition can
satisfy that binding.

**The NCTS value sets are authored over it.** Everything under
`healthterminologies.gov.au` expands against Australian edition content.

**Australian dialect.** The edition carries the `en-AU` language refsets, so preferred
terms and display validation match Australian usage rather than en-US.

## 3. Why loading International as well is the wrong move

It is tempting, because it would make the validator's default resolvable and the
warnings would stop. It stops them by validating Australian content against the wrong
edition.

**It converts a false error into a real one.** The single `error` in the AU PS report,
`Unable to find a profile match for #bisoprolol`, traces to the AMT required binding. If
International were loaded and the validator kept requesting it, AMT codes would be
absent from that edition and the binding would fail *legitimately*. The symptom moves
rather than resolves, and the new failure is harder to diagnose because it is correct.

**It buys nothing for international profiles either.** The AU PS suite also validates
against the IPS Bundle profile, which is the strongest case anyone could make for
loading International. Measured on the same bundle:

| Profile | International default | Australian edition |
|---|---|---|
| AU PS Bundle | 28 warnings / 19 info | **8 / 9** |
| IPS Bundle | 30 warnings / 28 info | **10 / 21** |

IPS validation gets *better* with the Australian edition selected, for the reason in §2:
the International content IPS is defined over is all present.

**It doubles the SNOMED index** for content that is already there, and adds a second
release train to keep current (International half-yearly, AU monthly).

**It makes edition selection ambiguous.** Ontoserver advertises a default edition via
`http://ontoserver.csiro.au/fhir/StructureDefinition/defaultsnomededition`, currently
`http://snomed.info/sct/32506021000036107`. With both loaded, a client that explicitly
requests International, which the FHIR validator does by default, silently gets
International, while a client that requests nothing gets Australian. Two clients, same
server, different answers, no error either way.

## 4. When you would want International on tx.dev

Stated for completeness, since none of these currently apply.

- If the server were repurposed to validate IGs whose value sets are bound to
  International-edition version URIs specifically, rather than to `http://snomed.info/sct`
  without a version.
- If something needed to assert that a code is valid in *plain* International, for
  example checking that an artefact intended for international publication contains no
  AU extension concepts. That is a conformance question the Australian edition cannot
  answer, because it would resolve those concepts happily.

Neither describes AU Core, AU PS, or the IPS profiles those suites validate against. If
either becomes real, load International **and** keep the per-suite `snomedCT` selection,
so each suite still states which edition it means. Do not rely on a server default to
disambiguate.

## 5. Where the selection lives

In the test kits, beside the terminology server they already configure:

```ruby
cli_context do
  txServer ENV.fetch('TX_SERVER_URL', 'https://tx.dev.hl7.org.au/fhir')
  snomedCT ENV.fetch('SNOMED_EDITION', 'au')
  noEcosystem true
end
```

`au` is an alias resolved by `SnomedUtilities.getCodeFromAlias` to `32506021000036107`.
Verified identical to passing the SCTID directly.

The test kit is the right home rather than a platform patch: it already owns `txServer`,
and the edition is only meaningful in relation to it. Splitting the pair across two
repositories would let them drift.

- `au-ps-inferno`: the suite's `cli_context`.
- `au-fhir-core-inferno`: `Constants.snomed_edition`, shared by all four suites and the
  local generator template.
- `inferno_suite_generator`: `suite.snomed_edition`, so newly generated kits inherit it.

## 6. Two things that bite when changing this

**Validator sessions ignore a changed context.** Inferno persists session ids in
`validator_sessions`, keyed on `(test_suite_id, suite_options, validator_name)` and never
on context content. The wrapper binds an engine to its session and ignores a changed
`cliContext` for an existing session id. Replaying the same bundle with the corrected
context against an existing session gave an unchanged 28/19; a fresh session gave 8/9.
Deployments must clear `validator_sessions` and restart the validator.

**Cached failures outlive the fix.** `$validate-code` responses, failures included, are
written to the terminology cache PVC with no TTL. The correction stops *new* failures
being cached but does not remove old ones. See
`templates/jobs/tx-cache-refresh.cronjob.yaml`.

---

## Reproduction

Validator-wrapper 1.0.78 (core 6.9.7) and 1.0.81 (core 6.9.12) behave identically, so
this is not a version regression and no version upgrade addresses it.

```bash
docker run -d --name v -p 3599:3500 -e SESSION_CACHE_DURATION=-1 \
  markiantorno/validator-wrapper:1.0.81

# Same bundle, same tx server, differing only in cliContext.snomedCT.
curl -sX POST http://localhost:3599/validate -H 'Content-Type: application/json' \
  --data-binary @request.json
```

with `request.json` carrying:

```json
{
  "cliContext": {
    "igs": ["hl7.fhir.au.ps#1.0.0"],
    "txServer": "https://tx.dev.hl7.org.au/fhir",
    "noEcosystem": true,
    "snomedCT": "au",
    "profiles": ["http://hl7.org.au/fhir/ps/StructureDefinition/au-ps-bundle"]
  },
  "filesToValidate": [{ "fileName": "Bundle/aups-basicsummary.json", "fileContent": "...", "fileType": "json" }],
  "sessionId": null
}
```

Omit `snomedCT` for the baseline. `infra/helm/inferno/files/warmer-bundle.json` is a copy
of the bundle used above.
