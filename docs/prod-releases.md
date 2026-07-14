# Prod releases (versioning + deployment records)

Prod deploys via GitOps: ArgoCD (`inferno-prod`, `targetRevision: master`) syncs
`infra/helm/inferno/values-prod.yaml`. The **merge of a promotion PR is the release gate**
and the deploy trigger. This doc covers the release identity and audit trail layered on
top of that flow.

## Flow

1. **Push to master** builds one released-flavour image tagged by commit SHA
   (`build-and-release-package.yaml`). Staging auto-updates via ArgoCD Image Updater.
2. The same workflow prepares a **prod-promotion PR** on branch `promote/prod-<sha>` that
   bumps `values-prod.yaml` to the built SHA. The PR body carries a changelog, risk flags,
   and a **proposed SemVer** (patch bump of the latest `vX.Y.Z` tag).
   - If a `PROMOTE_TOKEN` secret exists, the PR is **auto-opened as a draft**.
   - Otherwise a one-click prefilled compare link is printed in the run summary (fallback).
3. A human sets the version and merges (the gate):
   - **Default:** merge as-is to accept the proposed patch bump.
   - **Different level:** apply a `release:major` / `release:minor` / `release:patch`
     label (label wins over the title).
   - **Explicit version:** edit the PR title to end with `-> vX.Y.Z` (used when no
     `release:*` label is present).
4. On merge, `prod-release.yaml`:
   - resolves the version, aliases the SHA-tagged images to `vX.Y.Z` / `vX.Y.Z-nginx`
     in ghcr (no rebuild, digest-identical),
   - creates the annotated git tag + a **GitHub Release** (changelog since the previous tag),
   - records a deployment against the **`production` Environment**, waits for
     `https://inferno.hl7.org.au` to serve HTTP 200, then marks the deployment
     success/failure.

`values-prod.yaml` stays pinned to the **immutable SHA** (reproducible). `vX.Y.Z` is the
human-facing release identity (git tag + Release + image alias + Environment record).

## PROMOTE_TOKEN (auto-open the draft PR)

The default `GITHUB_TOKEN` cannot be used: PRs it opens do **not** trigger further
workflows, so `quality-control` would silently skip. Provision one of:

- **GitHub App token (recommended):** install a small App with `contents:write` +
  `pull_requests:write` on this repo, mint a token in-workflow with
  `actions/create-github-app-token`, and expose it as `PROMOTE_TOKEN`. Not user-bound.
- **Fine-grained PAT (pragmatic):** scope Contents + Pull requests to this repo, store as
  the `PROMOTE_TOKEN` repo secret. Tied to the issuing user; rotate periodically.

Absent the secret, the flow falls back to the prefilled compare link, so shipping this
without a token is safe.

## Rollback

A release is an immutable target, so rollback is a one-line promotion PR: point
`values-prod.yaml` (`imageUrl` / `platformImageUri`) back at the SHA of the prior release
(shown in that release's notes) and merge. ArgoCD reverts prod on sync. Cut a new patch
release from the rollback if you want the tag history to reflect it.

## Why the merge is the gate (not an Environment approval)

In GitOps, ArgoCD deploys from git regardless of whether any CI job ran. A GitHub
Environment "required reviewers" rule only gates a GitHub Actions job, so it would be
redundant with the promotion-PR review, not an additional gate. The `production`
Environment here is therefore used for **deployment records and verification**, not as an
approval gate. The gate is the human-merged, `quality-control`-checked promotion PR.
