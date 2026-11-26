# Preview environments

Every pull request can get its own short-lived, fully-deployed copy of Inferno —
useful for reviewing UI/content changes, exercising a test-kit gem bump, or sharing
a running build with reviewers before it merges.

## How to spin one up

1. Open a PR (against `master`, the trunk).
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
   │       ghcr.io/hl7au/au-fhir-inferno:<head-sha>-pr
   │
   └─►  ArgoCD ApplicationSet `inferno-previews` (in aehrc/sparked-argo)
           PR generator (filtered by the `preview` label) creates an Application
           `inferno-pr-<n>` that deploys the chart from the PR's HEAD commit into
           namespace `inferno-pr-<n>`, using the <head-sha>-pr image and an
           ephemeral in-namespace Postgres (no RDS).
```

> **One image serves the whole preview.** The static landing site and the `/suites` ->
> `/test-kits` redirects ship inside the application image and are served by Rack
> middleware, so the gateway sends `/` straight to the app on port 4567.

- **Hostname:** `pr-<n>.preview.inferno.sparked-fhir.com`, covered by the
  `*.preview.inferno.sparked-fhir.com` wildcard TLS cert + gateway listener.
- **Database:** an ephemeral in-namespace Postgres (Bitnami subchart), created and
  destroyed with the environment. No connection to dev/prod RDS.
- **Updates:** push more commits to the PR and the preview rebuilds and redeploys
  automatically (the image is re-tagged for the new HEAD commit).

## Previewing a test-kit (gem) change

Previews build with `Gemfile.dev`, which floors `au_core_test_kit` and `au_ps_inferno`
at a minimum released version (for example `>= 1.4.7`); `Gemfile.dev.lock` pins the exact
version. To preview a change to one of those kits:

1. Push your change to the kit repo (e.g. `hl7au/au-ps-inferno`) and note the commit SHA.
2. In an `au-fhir-inferno` branch, swap that gem's floor in `Gemfile.dev` for a
   `github:`/`ref:` pin to the commit and regenerate `Gemfile.dev.lock` (Ruby 3.3.12,
   clean `GEM_HOME`). Move it back to a floor once the kit commit is released.
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

- **Timing:** a GitHub webhook to the ApplicationSet controller drives refreshes, with a
  fallback poll every 2 minutes (`requeueAfterSeconds: 120` in
  `apps/inferno-previews.yaml`, `aehrc/sparked-argo`). The poll matters because GitHub
  can deliver the `labeled` webhook before its API shows the label, so a label added just
  after the PR opens is picked up by the poll rather than the webhook. Creation and
  teardown therefore start within about 2 minutes. The validator warmer is off in
  previews, so the first validation in each suite also waits for its engine to build.
- **Guardrails, not hardening:** every preview namespace gets an egress-baseline
  NetworkPolicy, Pod Security labels, a ResourceQuota and a LimitRange from the trusted
  `apps/inferno-preview-guardrails` chart in `aehrc/sparked-argo`, which the PR cannot
  modify. The egress policy blocks link-local addresses (instance metadata) and the VPC
  range; ingress is not restricted. A preview still runs unreviewed PR code, so don't
  treat it as a secure deployment.
- **Persistent dev** (`development.inferno.sparked-fhir.com`) is unaffected — previews
  are additive.
- **CI-build suites** do not run in previews: they need `Gemfile.ci-build` and
  `INFERNO_CI_BUILD_SUITES=true`, which only the permanent ci-build environment has. See
  [ci-build-environment.md](ci-build-environment.md).
