# Preview environments

Every pull request can get its own short-lived, fully-deployed copy of Inferno —
useful for reviewing UI/content changes, exercising a test-kit gem bump, or sharing
a running build with reviewers before it merges.

## How to spin one up

1. Open a PR (against `development` or `master`).
2. Add the **`preview`** label.

That's it. Within a few minutes a bot comment appears on the PR with the URL:

```
https://pr-<PR-number>.preview.inferno.sparked-fhir.com
```

The comment updates to ✅ **live** once the environment is serving.

> **Who can do this:** only collaborators with **Triage / Write** (or above) can apply
> labels, so only they can create preview environments. PRs from forks cannot create
> previews (they can't apply labels and can't push images).

## What happens behind the scenes

```
add `preview` label
   │
   ├─►  GitHub Actions (build-and-release-package.yaml)
   │       builds this PR's HEAD commit (dev-flavoured: Gemfile.dev) and pushes
   │       ghcr.io/hl7au/au-fhir-inferno:<head-sha>-pr  (+ -nginx-pr)
   │
   └─►  ArgoCD ApplicationSet `inferno-previews` (in aehrc/sparked-argo)
           PR generator (filtered by the `preview` label) creates an Application
           `inferno-pr-<n>` that deploys the chart from the PR's HEAD commit into
           namespace `inferno-pr-<n>`, using the <head-sha>-pr image and an
           ephemeral in-namespace Postgres (no RDS).
```

- **Hostname:** `pr-<n>.preview.inferno.sparked-fhir.com`, covered by the
  `*.preview.inferno.sparked-fhir.com` wildcard TLS cert + gateway listener.
- **Database:** an ephemeral in-namespace Postgres (Bitnami subchart), created and
  destroyed with the environment. No connection to dev/prod RDS.
- **Updates:** push more commits to the PR and the preview rebuilds and redeploys
  automatically (the image is re-tagged for the new HEAD commit).

## Previewing a test-kit (gem) change

Previews build with `Gemfile.dev`, which pins `au_core_test_kit` and `au_ps_inferno`
by git ref. To preview a change to one of those kits:

1. Push your change to the kit repo (e.g. `hl7au/au-ps-inferno`) and note the commit SHA.
2. In an `au-fhir-inferno` branch, bump that gem's `ref:` in `Gemfile.dev` and
   regenerate `Gemfile.dev.lock` (Ruby 3.3.6, clean `GEM_HOME`).
3. Open the PR, add the `preview` label — the preview runs your kit change.

## Teardown

The environment is **ephemeral**. It is removed automatically when you either:

- **close** the PR, or
- **merge** the PR (merging closes it), or
- **remove** the `preview` label.

ArgoCD deletes the `inferno-pr-<n>` Application and prunes the entire namespace —
app, validator, redis, and the ephemeral Postgres (including its volume). Nothing
lingers. Because merging also tears it down, a preview is a *pre-merge* review tool.

## Notes & limitations

- **Timing:** the ApplicationSet polls GitHub roughly every 30 minutes, so creation
  and teardown can take up to that long to begin (a webhook to make this instant is a
  possible future improvement). First start also includes a validator warmup (~5–10 min).
- **Not hardened:** preview namespaces have no NetworkPolicies (unlike dev/prod) — fine
  for ephemeral review environments, but don't treat a preview as a secure deployment.
- **Persistent dev** (`development.inferno.sparked-fhir.com`) is unaffected — previews
  are additive.
