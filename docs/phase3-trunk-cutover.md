# Phase 3 — Trunk cutover runbook

Status: **draft / not yet executed** · Owner: Kyle Pettigrew · Drafted: 2026-06-23

The design + step-by-step checklist for collapsing the two long-lived branches into a
single trunk. This document is reviewed and merged first; **execution happens in a
separate, deliberate session** (low prod traffic) using the checklist below.

> **Scope correction vs the original roadmap.** The roadmap said "collapse
> development + master → `main`". On review, the rename is **cosmetic** — trunk-based
> development is about having *one* long-lived branch, not its name. Renaming would force
> a default-branch switch (**admin-only**) and re-point every clone for no functional
> gain. So **the trunk stays `master`**, and Phase 3 carries **no hard admin dependency**
> — branch protection is a fast-follow, not a gate (see below).

---

## Goal / end state

One trunk. Feature work flows: **branch → PR → `master` → auto-deploy to staging →
promotion PR → prod.**

- `master` = trunk. `development` retired.
- Every push to `master`: build **one** image `:<sha>`, auto-deploy it to staging, and
  open a prod-promotion PR for the *same* image (build once, deploy many).
- **Staging** = the env currently at `development.inferno.sparked-fhir.com`
  (conceptually re-labelled; hostname unchanged), now a **prod mirror** (released-flavour).
- **Prod** = promotion PR (human gate), shipping the identical `:<sha>` artifact staging
  already ran.
- **Bleeding-edge / unreleased kit commits** live in **preview environments**
  (Gemfile.dev), not in a persistent branch. Previews are unchanged.

---

## Why no admin is required (and the protection nuance)

- No rename → no default-branch change → **no admin action to cut over.**
- We can do every cutover step with `maintain` on au-fhir-inferno + our admin on
  `aehrc/sparked-argo`.
- **Branch protection is not a blocker.** `master` has none today, so going trunk is *not
  less* protected — same (zero) enforcement. It's a fast-follow ask to Brett, not a gate.
- Honest nuance: protection is *more valuable* under trunk, because today the
  `development → master` merge is an implicit human checkpoint that disappears. Mitigations
  that hold without protection: **prod keeps its human gate** (you merge the promotion PR),
  and **`quality-control` already runs on pushes to `master`** (advisory signal). So add
  protection soon — but it doesn't block the cutover.

---

## Decisions to confirm (defaults baked; adjust in review)

1. **Trunk = `master`, no rename.** *(recommended)*
2. **Build once, prod-flavour trunk — THE consequential decision.** `master` builds a
   single released-flavour image (`Gemfile` + `web:generate_prod`); **staging and prod run
   the same artifact.** Bleeding-edge (Gemfile.dev / unreleased kit SHAs) moves to preview
   envs. *Alternative:* keep building two flavours (staging = bleeding-edge, prod =
   released) — but then staging ≠ the artifact you promote, which throws away a core trunk
   benefit. **Recommended: build once.** This also makes `Gemfile.dev`'s only job "preview
   override", matching the earlier decision.
3. **Staging deploys automatically via the existing image write-back** (repointed to
   `master` + `values-dev.yaml`, `[skip ci]`; `infra/**` is paths-ignored so no rebuild
   loop). *(recommended)*
   > Corrects an earlier suggestion of "promotion-PR for staging": a promotion PR isn't
   > *auto*, and the roadmap wants staging to auto-track the trunk. Retiring the write-back
   > entirely (ArgoCD Image Updater) is a clean **future** improvement, not part of the cutover.
4. **Prod = promotion PR** (unchanged human release gate).
5. **`Gemfile.dev` = preview-override only.** Trunk `Gemfile` stays released-form (`au_ps`
   remains git-SHA-pinned until it can publish to RubyGems). The "trunk Gemfile is
   git-ref-free" guard is **deferred** until AU PS releases.
6. **Keep filenames / ArgoCD app names** (`values-dev.yaml`, `inferno-dev` Application) to
   minimise churn; re-label to "staging" conceptually. Optional rename later.
7. **Branch protection on `master`** (require PR + 1 review + passing `quality-control`) =
   fast-follow ask to Brett.

---

## Cutover steps

Legend: **[us]** = doable with current access · **[Brett]** = admin, fast-follow.

1. **[us] Bring `master` current.** Final `development → master` merge **commit** (never
   squash — preserves ancestry). Confirm `quality-control` is green on `master`.
2. **[us] Swap in the trunk build workflow.** Replace
   `.github/workflows/build-and-release-package.yaml` with the trunk version (drafted at
   `docs/phase3/build-and-release-package.yaml`): drops the `development` trigger and the
   dev-flavour trunk build; `master` builds `:<sha>` once, writes the staging tag back to
   `values-dev.yaml`, and opens the prod-promotion PR. Preview path unchanged.
3. **[us · sparked-argo] Repoint staging.** `inferno-dev` Application
   `targetRevision: development → master`. (Prod already tracks `master`.)
4. **[us] Smoke test.** Push a trivial commit to `master` → `:<sha>` builds → staging
   (`development.inferno…`) auto-updates and is healthy → a prod-promotion PR appears (don't
   merge unless actually releasing).
5. **[us] Retire `development`.** Announce; stop deploying from it; **after** staging-from-
   master is proven, delete the branch (keep an archived tag/ref for safety).
6. **[Brett] Branch protection** ruleset on `master`: require PR + 1 review + passing
   `quality-control`. *(fast-follow)*
7. **[us] Tidy up.** Update docs / CODEOWNERS / PR template to trunk language; mark Phase 3
   complete in `docs/cicd-overhaul-plan.md` + memory.

---

## Verification checklist

- [ ] Staging serves the released-flavour build of the latest `master` commit.
- [ ] Prod is untouched until a promotion PR is merged (and ships the same `:<sha>`).
- [ ] Preview envs still spin up on a `preview`-labelled PR.
- [ ] `quality-control` runs on pushes to `master`.
- [ ] No rebuild loop from the staging write-back (`[skip ci]` + `infra/**` paths-ignore).

---

## Rollback

Low-risk — `master` is never renamed or destroyed, and **prod stays human-gated
throughout** (the promotion PR is the only path to prod), so prod cannot auto-break.

1. Revert the workflow commit (restores the development/master split behaviour).
2. Repoint the `inferno-dev` Application `targetRevision` back to `development`.
3. `development` still exists (don't delete until proven) → resume as before.

---

## Handover — kickoff prompt for the execution session

```
Execute Phase 3 (trunk cutover) for AU Inferno. Read docs/phase3-trunk-cutover.md and
memory `inferno-cicd-overhaul-roadmap` first. Trunk = master (no rename). Follow the
"Cutover steps" checklist; the trunk build workflow is pre-drafted at
docs/phase3/build-and-release-package.yaml. Confirm the "Decisions to confirm" defaults
with me before step 2. Prod stays human-gated via the promotion PR — do not merge a
promotion PR without my go. Do the development→master merge, swap the workflow, repoint
the inferno-dev ArgoCD app (sparked-argo) to master, smoke-test staging, then retire
development. Branch protection is Brett's fast-follow, not a blocker. Open PRs; verify
each with helm template + watching ArgoCD sync.
```
