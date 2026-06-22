# Inferno CI/CD Overhaul Plan

Status: **active** · Owner: Kyle Pettigrew · Last updated: 2026-06-23

This document is the reference for overhauling how the AU FHIR Inferno platform is
built, deployed, versioned, and tracked. It covers four repositories:

| Repo | Role |
| --- | --- |
| `hl7au/au-fhir-inferno` | The Inferno website + harness (this repo). Its `Gemfile` is the test-kit integration point. |
| `hl7au/au-fhir-core-inferno` | AU Core test-kit gem (`au_core_test_kit`). Released on RubyGems. |
| `hl7au/au-ps-inferno` | AU PS test-kit gem (`au_ps_inferno`). Not yet released. |
| `aehrc/sparked-argo` | ArgoCD GitOps repo that deploys/hosts the app. **Different org (aehrc).** |

Work is tracked on the [Inferno Testing Framework board](https://github.com/orgs/hl7au/projects/2).

---

## How it works today

### Deploy flow (branch → environment)

```
push to development ─▶ CI builds <sha>-dev images ─▶ CI seds values-dev.yaml and
                       commits the tag back to development ([skip ci]) ─▶ ArgoCD
                       (sparked-argo, targetRevision: development) ─▶ dev-inferno
                       ─▶ https://development.inferno.sparked-fhir.com

push to master ──────▶ CI builds <sha>-prod images (NO write-back) ─▶ a human
                       manually edits values-prod.yaml ─▶ ArgoCD
                       (targetRevision: master) ─▶ prod-inferno
                       ─▶ https://inferno.hl7.org.au
```

- Helm chart lives here at `infra/helm/inferno`; ArgoCD applies `values.yaml` then
  `values-{dev,prod}.yaml`.
- GitOps changes (sparked-argo) are **out of scope for the board**: app/content dev is
  done in hl7au; sparked infra deploys it. "Merged to an env branch = deployed to that
  env" is sufficient — no cross-org tracking token is needed.

### Test-kit supply chain

`au-fhir-inferno` is not a gem; its `Gemfile` pins the kits. Today they are pinned by
**raw git SHA** and bumped by hand. `au_core_test_kit` has a released-gem fallback that
was toggled by commenting lines per branch — the source of the merge pain.

### Key facts

- `development` is **54 commits ahead / 0 behind** `master`.
- `tx.dev.hl7.org.au` is the terminology server for **all** environments — this is
  **intentional** (it carries the latest terminology releases the tests need), not a
  misconfiguration. Do not add a prod override.
- No branch protection exists on `master` or `development` in any repo.

---

## Decisions

| Decision | Choice |
| --- | --- |
| **Roadmap shape** | Phased: **pragmatic → preview envs → trunk-based**. Trunk is the destination; phasing de-risks it and almost nothing is throwaway. |
| **Dev/prod dependency split** | `Gemfile.dev` + committed `Gemfile.dev.lock`, selected via `BUNDLE_GEMFILE`; base `Gemfile`/lock stay released-form on both branches; **frozen** builds. |
| **Prod promotion** | Automated **PR** bumping `values-prod.yaml` on merge to `master` (human-merged = release gate). |
| **Governance** | Protect **`master` only** for now (PR + 1 review + passing checks); `development` stays direct-push for dev speed. |
| **Board** | Build on existing project #2. Auto-add via per-repo Actions; **filter dependabot/automated PRs off the board**. |
| **GitOps on board** | No. Tracked by env-branch merges only. |

---

## Phase 1 — Pragmatic fixes

> Removes the daily friction and makes prod safe, without changing the branch model.

### 1.1 — Gemfile split *(done — see PR)*
Base `Gemfile` (prod/released) + `Gemfile.common` (shared) + `Gemfile.dev` (bleeding-edge
SHAs) with its own `Gemfile.dev.lock`, selected by `BUNDLE_GEMFILE`. Frozen Docker builds.
Result: prod `Gemfile`/`Gemfile.lock` are identical on both branches → `development →
master` merges never conflict on dependencies and cannot leak unreleased versions to prod.
`validation_test_kit` is now pinned (it previously floated, including in prod).

### 1.2 — Automated prod-promotion PR
On merge to `master`, CI opens a PR bumping `values-prod.yaml` `imageUrl`/`platformImageUri`
to the new `<sha>-prod` tags. Merging it is the release gate. Stop the self-referential dev
write-back to the triggering branch (add concurrency/rebase as an interim). Reconcile the
sparked-argo ADR (`adr-ci-writeback-vs-image-updater.md`), which claims all apps use
write-back while prod does not.

### 1.3 — Reproducibility & cleanup
Pin `nginx` and the dev `validator-wrapper` (`:latest` today). Remove dead config (base
`values.yaml` image SHA, unused `prod` branch trigger, `usesWrapper`). Consolidate the two
near-duplicate Terraform workflows and add a manual approval gate before prod `terraform
apply` (currently auto-approves on push to master).

### 1.4 — Governance + board
Protect `master` (PR + 1 review + passing `quality-control`); add `CODEOWNERS`. Add
`actions/add-to-project` workflows in each hl7au repo → project #2, filtering out
dependabot/automated PRs. Shared `PULL_REQUEST_TEMPLATE.md` (via `hl7au/.github`) requiring
a `Closes #…` link. Unify priority on the board's `Priority` field; consider an `Area`
field. One-time backfill of existing open items.

### 1.5 — Test-kit release maturity *(cross-cutting; unblocks consuming by version)*
- **au-fhir-core-inferno**: code is at `1.4.2` but only `1.4.0` is published — cut the
  missing release, add a tag↔`version.rb` consistency check, then move this repo's Gemfile
  from the SHA pin to `~> 1.4`.
- **au-ps-inferno**: add `version.rb`, adopt tags + Releases, publish to RubyGems via the
  existing `RUBYGEMSKEY` secret (the name `au_ps_inferno` is unclaimed/claimable), rename
  `au_ips_inferno.gemspec` → `au_ps_inferno.gemspec`. Then pin by version here.
- Add downstream-bump automation: a kit release opens a Gemfile-bump PR here (via a PAT so
  CI runs).

---

## Phase 2 — Preview environments

Per-PR ephemeral deploys so any branch can get a live URL.

- ArgoCD **ApplicationSet** (PR generator) on `au-fhir-inferno` → namespace `inferno-pr-<n>`,
  hostname `pr-<n>.dev.inferno.sparked-fhir.com`, auto-deleted on PR close.
- **Wildcard TLS + DNS** (`*.dev.inferno.sparked-fhir.com`) so new hostnames need no
  per-branch gateway edits (static per-FQDN listeners are the current blocker).
- Loosen the `proj-inferno` AppProject to an `inferno-*` namespace pattern (or a dedicated
  ephemeral project); keep prod tight.
- Chart hygiene (prereq): unify namespacing (`.Release.Namespace` vs `.Values.namespace`),
  drop the duplicated inline overrides in `inferno-dev.yaml`.
- Per-PR data/secrets: ephemeral Postgres-in-namespace vs schema-per-PR; reusable IAM/secret
  strategy.

---

## Phase 3 — Trunk cutover

- Collapse `development` + `master` → **`main`**. `main` HEAD auto-deploys to a persistent
  **staging** env; `main` → **prod** via the Phase 1 promotion PR.
- Repoint ArgoCD `targetRevision` to `main`; retire the bespoke dev write-back entirely.
- Feature work → short-lived branch → preview env → PR → merge → delete branch+env.
- "Dev tracks bleeding-edge" now lives in `Gemfile.dev`, not a branch — so the cutover is
  small and low-risk by this point. Move branch protection `master` → `main`.

---

## Open items needing a decision

- **Auto-add token**: create a fine-grained org token (Org projects R/W + repo issues/PRs
  read) stored as an org secret. (Approved in principle.)
- **Org-level `RUBYGEMSKEY`**: unverified (gh 403). Each kit repo already has its own
  `RUBYGEMSKEY`, so per-repo publishing is unblocked regardless. Trusted publishing (OIDC)
  is the cleaner long-term option.
