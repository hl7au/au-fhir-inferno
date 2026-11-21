# Prod releases (versioning + deployment records)

Prod deploys via GitOps: ArgoCD (`inferno-prod`, `targetRevision: prod`) renders the chart
and `infra/helm/inferno/values-prod.yaml` from the **`prod` branch**, which only a merged
promotion PR moves. The **merge of a promotion PR is the release gate** and the deploy
trigger. This doc covers the prod branch, the release identity and the audit trail layered
on top of that flow.

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
   - fast-forwards the `prod` branch to the merge commit (this is the deploy),
   - resolves the version, aliases the SHA-tagged image to `vX.Y.Z`
     in ghcr (no rebuild, digest-identical),
   - creates the annotated git tag + a **GitHub Release** (changelog since the previous tag),
   - records a deployment against the **`production` Environment**, waits for
     `https://inferno.hl7.org.au` to serve HTTP 200, then marks the deployment
     success/failure.

`values-prod.yaml` stays pinned to the **immutable SHA** (reproducible). `vX.Y.Z` is the
human-facing release identity (git tag + Release + image alias + Environment record).

## The prod branch

`prod` is an environment branch: it always points at a commit on `master`, namely the
merge commit of the latest promotion PR. Moving it is the only thing that changes prod.

- **Chart and image move together.** The chart templates, `values.yaml` and
  `values-prod.yaml` that prod renders are the ones on `master` when the promotion PR
  merged, which is the same combination staging was running.
- **An ordinary merge to `master` does not reach prod.** A chart or `values-prod.yaml`
  change waits for the next promotion. If there is no app change to carry it, run
  **Build and Release Inferno Image** by hand on `master` (Actions, Run workflow): it
  builds that commit and opens a promotion PR as usual.
- **Freezes are a property of the branch.** During an event freeze nobody merges a
  promotion PR, and nothing else can move prod. The Argo CD sync window on the `inferno`
  project (in `aehrc/sparked-argo`) is the backstop.
- **Who moves it.** `prod-release.yaml` fast-forwards it (never a force push), using
  `PROMOTE_TOKEN` when set. GitHub refuses a ref update that changes files under
  `.github/workflows/` unless the token has the **Workflows** permission, which the
  default `GITHUB_TOKEN` can never have, so `PROMOTE_TOKEN` needs Contents and Workflows
  read and write. If the step fails, prod stays where it was and a release owner runs the
  command the job prints (`git push origin <merge sha>:refs/heads/prod`).

## PROMOTE_TOKEN (auto-open the draft PR)

The default `GITHUB_TOKEN` cannot be used: PRs it opens do **not** trigger further
workflows, so `quality-control` would silently skip. Provision one of:

- **GitHub App token (recommended):** install a small App with `contents:write`,
  `pull_requests:write` and `workflows:write` on this repo, mint a token in-workflow with
  `actions/create-github-app-token`, and expose it as `PROMOTE_TOKEN`. Not user-bound.
- **Fine-grained PAT (pragmatic):** scope Contents, Pull requests and Workflows (read and
  write) to this repo, store as
  the `PROMOTE_TOKEN` repo secret. Tied to the issuing user; rotate periodically.

Absent the secret, the flow falls back to the prefilled compare link, so shipping this
without a token is safe.

## Rollback

Every release tag `vX.Y.Z` points at its promotion merge commit, so a rollback moves
`prod` back to the previous tag. That restores the chart, `values-prod.yaml` and the image
of that release together. A release owner runs:

```sh
git fetch origin --tags
git push --force origin 'v1.2.2^{commit}:refs/heads/prod'   # the release to return to
```

The release before the `prod` branch existed is the exception: prod then rendered the
chart from `master`, so the `v1.2.2` tag's chart is older than what prod last ran. To roll
back the first promotion after the switch, move `prod` to the commit it was created at
(recorded when it was bootstrapped), not to `v1.2.2`.

ArgoCD syncs prod from the moved branch within its poll interval. The next promotion
fast-forwards `prod` from there as usual, because the old tag is an ancestor of every
later merge commit. Forward-only database migrations mean a rollback across a migration
needs checking first.

## Why the merge is the gate (not an Environment approval)

In GitOps, ArgoCD deploys from git regardless of whether any CI job ran. A GitHub
Environment "required reviewers" rule only gates a GitHub Actions job, so it would be
redundant with the promotion-PR review, not an additional gate. The `production`
Environment here is therefore used for **deployment records and verification**, not as an
approval gate. The gate is the human-merged, `quality-control`-checked promotion PR.
