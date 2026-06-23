# Inferno CI/CD Overhaul Plan

Status: **complete** (Phases 1–3 + preview envs shipped) · Owner: Kyle Pettigrew · Last updated: 2026-06-23

This document is the reference for overhauling how the AU FHIR Inferno platform is
built, deployed, versioned, and tracked. It covers four repositories:

| Repo | Role |
| --- | --- |
| `hl7au/au-fhir-inferno` | The Inferno website + harness (this repo). Its `Gemfile` is the test-kit integration point. |
| `hl7au/au-fhir-core-inferno` | AU Core test-kit gem (`au_core_test_kit`). Released on RubyGems. |
| `hl7au/au-ps-inferno` | AU PS test-kit gem (`au_ps_inferno`). Not yet released. |
| `aehrc/sparked-argo` | ArgoCD GitOps repo that deploys/hosts the app. **Different org (aehrc).** |

Work is tracked on the [Inferno Testing Framework board](https://github.com/orgs/hl7au/projects/2).

> **Just want to ship a change?** See [`dev-workflow.md`](dev-workflow.md) — a short,
> example-driven walkthrough of branch → PR → preview → staging → prod. This document is the
> deeper design/decision reference.

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
- **Phase 3 — trunk cutover: done (2026-06-23).** `master` is the single trunk (no rename
  to `main` — cosmetic). Every push to `master` builds one released-flavour image; ArgoCD
  Image Updater detects the new tag and deploys it to staging, and the build opens a
  prod-promotion PR for the same artifact. `inferno-dev` (ArgoCD) tracks `master`;
  `development` is retired (archived at the `archive/development` tag).
- **Branch protection on `master` is now ACTIVE** (require PR + 1 review + passing
  `quality-control`; force-push/deletion blocked; admin bypass). Staging deploys via
  ArgoCD Image Updater (CI no longer pushes to `master`), which is what unblocked the
  ruleset — see "Staging deploys" below.
- **Still needs Brett (org-only):** the `ADD_TO_PROJECT_PAT` org secret (board auto-add is a
  no-op until it exists) and push on `inferno_suite_generator`. Repo admin + board admin
  were granted (2026-06-23).

---

## How it works today

### Deploy flow (branch → environment)

```
push to master ──▶ CI builds ONE released-flavour image :<sha> (build once) ─┬─▶ ArgoCD Image
                   Updater (in sparked-argo) detects the new tag, writes it to the deploy repo
                   (image-values.yaml) ─▶ ArgoCD (inferno-dev, targetRevision: master)
                   ─▶ dev-inferno (staging) ─▶ https://development.inferno.sparked-fhir.com
                                                                              │
                                                                              └─▶ pushes a
                   promote/prod-<sha> branch with the SAME tag in values-prod.yaml + a
                   one-click PR link ─▶ a human merges that PR (release gate) ─▶ ArgoCD
                   (inferno-prod targetRevision: master) ─▶ prod-inferno
                   ─▶ https://inferno.hl7.org.au
```

Staging and prod run the **same artifact** (build once, deploy many). Bleeding-edge /
unreleased test-kit commits (`Gemfile.dev`) live in per-PR preview environments, not a
persistent branch. The CI build **pushes nothing back to `master`** — staging tracks the
registry via ArgoCD Image Updater, and prod moves only via the human-merged promotion PR.
This is what lets `master` be branch-protected (no CI bot bypass needed).

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

- `master` is the single trunk; `development` was retired at the Phase 3 cutover
  (archived at the `archive/development` tag).
- `tx.dev.hl7.org.au` is the terminology server for **all** environments — this is
  **intentional** (it carries the latest terminology releases the tests need), not a
  misconfiguration. Do not add a prod override.
- `master` is branch-protected on `au-fhir-inferno`: PRs require 1 review + a passing
  `quality-control` check; force-push and deletion are blocked (admin bypass retained).

### Permissions reality

We now have **repo admin** on `hl7au/au-fhir-inferno` (+ `au-ps-inferno`) and **board admin**
on project #2, granted by Brett (2026-06-23). With that we set the `master` ruleset and the
required `quality-control` check. The only remaining owner-gated items are **org-level**: the
`ADD_TO_PROJECT_PAT` org secret and push on `inferno_suite_generator` — see Track B.

---

## Decisions

| Decision | Choice |
| --- | --- |
| **Roadmap shape** | Phased: **pragmatic → preview envs → trunk-based**. Trunk is the destination; phasing de-risks it and almost nothing is throwaway. |
| **Dev/prod dependency split** | `Gemfile.dev` + committed `Gemfile.dev.lock`, selected via `BUNDLE_GEMFILE`; base `Gemfile`/lock stay released-form on both branches; **frozen** builds. |
| **Prod promotion** | Automated **PR** bumping `values-prod.yaml` on merge to `master` (human-merged = release gate). |
| **Governance** | Trunk `master` is protected (PR + 1 review + passing `quality-control`) — **active**. Post-cutover there is no `development`; all work flows through `master` PRs. |
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

## Phase 3 — Trunk cutover — **done (2026-06-23)**

Executed per `docs/phase3-trunk-cutover.md`. Trunk = **`master`** — the rename to `main` was
dropped as cosmetic (trunk-based development means *one* long-lived branch, not its name), which
also removed the only hard admin dependency, so the cutover was done with `maintain` + sparked-argo admin.

- Final `development → master` merge (#92); the trunk build workflow replaced the dev/master
  split (#93) — `master` builds one released-flavour image.
- ArgoCD `inferno-dev` repointed `development → master` (sparked-argo #39); `inferno-prod`
  already tracked `master`. Both environments now render from `master` and run the same artifact.
- Smoke-tested end-to-end: push to `master` → build → staging auto-deploy (Healthy, HTTP 200) →
  prod-promotion PR. `development` retired (archived at `archive/development`).
- Feature work → short-lived branch → PR → `master` → auto-staging → promotion PR → prod.
  Bleeding-edge lives in `Gemfile.dev` + preview envs, not a branch.
- **Done (fast-follow completed):** the staging write-back was retired in favour of ArgoCD
  Image Updater (CI no longer pushes to `master`), and the `master` ruleset is now active
  (PR + 1 review + passing `quality-control`).

---

## Track B — owner (Brett) actions

Granted 2026-06-23: **repo admin** on `hl7au/au-fhir-inferno` (+ `au-ps-inferno`) and **board
admin** on project #2. With those, branch protection / the `master` ruleset and the required
`quality-control` check were set up — **done**. Only org-level items remain.

| Item | Status |
| --- | --- |
| ~~Repo admin on `au-fhir-inferno` + `au-ps-inferno`~~ | **Granted.** |
| ~~Branch protection / ruleset on `master`~~ (PR + 1 review + passing `quality-control`) | **Active.** Prod still gated by the human-merged promotion PR; CODEOWNERS auto-requests reviewers. |
| ~~Admin on the project board~~ ([Inferno Testing Framework](https://github.com/orgs/hl7au/projects/2)) | **Granted.** |
| **Org secret `ADD_TO_PROJECT_PAT`** + a fine-grained org PAT (Projects R/W + repo Issues/PRs read) | **Outstanding (org-only).** `add-to-project` workflow is merged but a graceful no-op until the secret exists; items added manually via `gh` meanwhile. |
| **Push/maintain on `hl7au/inferno_suite_generator`** *(least important)* | **Outstanding (org-only).** Parked; AU PS stays git-ref-pinned, not RubyGems-released. |

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
- ~~**`prod` branch trigger**~~ — **resolved:** `build-and-release-package.yaml` builds on
  pushes to the trunk `master` + `preview`-labelled PRs only; no `prod`/`development` branch
  trigger remains.
- **Terraform consolidation**: merge the two near-duplicate Terraform workflows and add a
  prod-`apply` gate via `workflow_dispatch` (no-admin) rather than GitHub Environments.
- **Org-level `RUBYGEMSKEY`**: unverified (gh 403). Each kit repo already has its own
  `RUBYGEMSKEY`, so per-repo publishing is unblocked regardless. Trusted publishing (OIDC)
  is the cleaner long-term option.
- **CODEOWNERS owners**: seeded with `@KyleOps`; set the real owners/team.
