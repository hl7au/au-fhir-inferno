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

## Current state (2026-06-23)

- **Phase 1 — pragmatic fixes: shipped to prod.** `Gemfile.dev` split, automated
  prod-promotion (push a `promote/prod-<sha>` branch + a human merges it — no admin
  needed), reproducibility cleanup, CODEOWNERS + PR template, board auto-add workflow.
  `development → master` was merged (#79); prod runs released `au_core` 1.4.2 + AU PS.
- **Phase 2 — preview environments: complete and validated end-to-end.** Labelling a PR
  `preview` spins up an ephemeral per-PR deploy at
  `pr-<n>.preview.inferno.sparked-fhir.com`; closing/merging/unlabelling tears it down.
  See the dedicated section below and `docs/preview-environments.md`.
- **Phase 3 — trunk cutover: not started.** Next major phase.
- **Blocked on Brett (admin/org actions):** branch protection on `master`,
  `ADD_TO_PROJECT_PAT` org secret, and a set of new repo/board-admin asks (Track B).

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

### Permissions reality

The team currently has the **`maintain`** role on these repos, not **`admin`**. So we
can: push branches, merge PRs, create releases, and add/modify any files or workflows.
We **cannot**: set branch protection/rulesets, change repo Actions settings, or create
repo/org secrets. Those few admin/org actions are batched into **Track B** below for the
repo/org owner (Brett). Everything else proceeds through normal PR / merge / Actions.
**Update (2026-06-23):** requested full repo admin (au-fhir-inferno + au-ps-inferno) + board
admin + generator push from Brett — see Track B.

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

## Phase 1 — Pragmatic fixes *(shipped to prod)*

> Removes the daily friction and makes prod safe, without changing the branch model.
> Shipped via the `development → master` merge (#79); prod runs released `au_core` 1.4.2.

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

## Phase 2 — Preview environments *(complete — validated end-to-end 2026-06-22)*

Per-PR ephemeral deploys. **Add the `preview` label to a PR** → a live environment at
`https://pr-<n>.preview.inferno.sparked-fhir.com`; close / merge / unlabel tears it down.
Full user-facing guide: `docs/preview-environments.md`.

**How it works**

```
add `preview` label
   ├─► build-and-release-package.yaml builds the PR HEAD (Gemfile.dev) and pushes
   │     ghcr.io/hl7au/au-fhir-inferno:<head-sha>-pr  (+ -nginx-pr)
   ├─► preview-comment.yaml posts a sticky PR comment with the URL, polls, flips to "live"
   └─► ArgoCD ApplicationSet `inferno-previews` (sparked-argo) — GitHub PR generator
         filtered by the `preview` label → Application `inferno-pr-<n>` deploying the
         chart from the PR HEAD into namespace `inferno-pr-<n>`, with the <head-sha>-pr
         image and an ephemeral in-namespace Postgres.
```

**What shipped**

- **PR-generator ApplicationSet** `apps/inferno-previews.yaml` (sparked-argo #37). Anonymous
  GitHub polling (repo is public), 30-min requeue.
- **Per-PR image build** — `build-and-release-package.yaml` builds `preview`-labelled PRs by
  HEAD SHA, dev-flavoured (au-fhir-inferno #84).
- **Wildcard TLS + DNS** `*.preview.inferno.sparked-fhir.com` + gateway listener (`from: All`)
  (sparked-argo #35).
- **AppProject** allows `inferno-pr-*` namespaces (sparked-argo #36).
- **Ephemeral in-namespace Postgres** via the chart's `postgresql.enabled` toggle. Two chart
  bugs found + fixed by the first live run: double-quoted in-namespace `POSTGRES_HOST` (#84),
  and the dead `docker.io/bitnami/postgresql` tag → `bitnamilegacy` (#85). See
  [`preview-postgres-bitnamilegacy`].
- **Teardown** — `createNamespace` value + `templates/namespace.yaml` make ArgoCD *manage*
  the namespace so the finalizer prunes it (was lingering empty); au-fhir-inferno #87 +
  sparked-argo #38.
- **PR comment** — `preview-comment.yaml` sticky live-link comment (au-fhir-inferno #86).

**Access control** — only Triage+/Write collaborators can apply labels, and fork PRs can't
push images, so the `preview` label *is* the gate. No extra guard needed.

**Optional follow-ups** — a GitHub webhook to replace the 30-min poll (creation/teardown
within seconds); preview namespaces are intentionally un-hardened (no NetworkPolicies).

---

## Phase 3 — Trunk cutover

- Collapse `development` + `master` → **`main`**. `main` HEAD auto-deploys to a persistent
  **staging** env; `main` → **prod** via the Phase 1 promotion PR.
- Repoint ArgoCD `targetRevision` to `main`; retire the bespoke dev write-back entirely.
- Feature work → short-lived branch → preview env → PR → merge → delete branch+env.
- "Dev tracks bleeding-edge" now lives in `Gemfile.dev`, not a branch — so the cutover is
  small and low-risk by this point. Move branch protection `master` → `main`.

---

## Track B — needs the repo/org owner (Brett)

Batched admin/org actions we can't perform with `maintain`. Each has a no-admin interim
so work continues meanwhile. **Email sent to Brett 2026-06-23** requesting the access below.

| Item | Why it needs admin | Interim |
| --- | --- | --- |
| **Repo admin on `hl7au/au-fhir-inferno` + `hl7au/au-ps-inferno`** | To implement PR gates (branch protection / rulesets, required checks) + wire up integration and unit tests. Subsumes the branch-protection and Actions-settings asks below. | Work proceeds on `maintain`; gates are conventions (human-merge) not enforcement. |
| **Branch protection / ruleset on `master`** (require PR + 1 review + passing `quality-control`) | Repo-admin only (covered by the repo-admin ask above) | Prod gate is "a human merges the promotion PR" — works, just not enforced. CODEOWNERS auto-requests reviewers. |
| **Admin on the project board** ([Inferno Testing Framework](https://github.com/orgs/hl7au/projects/2)) | To manage fields/automation/views for tracking | Board used as-is; items added manually via `gh` (`project` scope). |
| **Org secret `ADD_TO_PROJECT_PAT`** + approve a fine-grained org PAT (Projects R/W + repo Issues/PRs read) | Org/repo-admin only | `add-to-project` workflow is merged but a graceful no-op until the secret exists. |
| **Push/maintain on `hl7au/inferno_suite_generator`** *(least important)* | To shorten the generated-filename scheme + regenerate (see below) | Parked; AU PS stays git-ref-pinned, not RubyGems-released. |

Explicitly **not** needed: the "Allow GitHub Actions to create and approve pull requests"
setting — the prod-promotion workflow was reworked to push a branch + surface a one-click
PR link, so it needs only `contents: write`.

### AU PS RubyGems release — blocked on the generator (inferno_suite_generator#22)

`au_ps_inferno` cannot be published to RubyGems: the generator emits filenames that exceed
the **100-char gem/tar limit**, so `gem build` fails. The generator
(`hl7au/inferno_suite_generator`) needs its filename scheme shortened and the AU PS kit
regenerated. Until then AU PS stays **git-ref-pinned** in `Gemfile`/`Gemfile.dev`. Pavel will
hit the same limit. Tracked at `hl7au/inferno_suite_generator#22`.

## Open items needing a decision

- ~~**Dev validator image** `markiantorno/validator-wrapper:latest`~~ — **decided:** dev
  intentionally tracks latest for speed (like the tx server); prod stays pinned. Do not pin dev.
- ~~**`prod` branch trigger**~~ — **resolved:** `build-and-release-package.yaml` was rewritten
  (master/development pushes + master PRs + `preview`-labelled PRs); no `prod` branch trigger remains.
- **Terraform consolidation**: merge the two near-duplicate Terraform workflows and add a
  prod-`apply` gate via `workflow_dispatch` (no-admin) rather than GitHub Environments.
- **Org-level `RUBYGEMSKEY`**: unverified (gh 403). Each kit repo already has its own
  `RUBYGEMSKEY`, so per-repo publishing is unblocked regardless. Trusted publishing (OIDC)
  is the cleaner long-term option.
- **CODEOWNERS owners**: seeded with `@KyleOps`; set the real owners/team.
