# The ci-build environment

One permanent environment that runs each test kit's CI-build suite, the suite generated
from the IG's CI build on build.fhir.org rather than from a published release. Testers
reach it from a radio on development.inferno's kit pages. Production never shows it.

The kit side of this (how each kit generates the suite and keeps its `ci-build` branch
fresh) is in [kit-ci-build-contract.md](kit-ci-build-contract.md). This file is the
aggregator side.

## Why a separate environment

Staging (`development.inferno.sparked-fhir.com`) and production run one released-flavour
image built from `Gemfile` ([phase3-trunk-cutover.md](phase3-trunk-cutover.md)), so a
suite that changes every night cannot live in it. The ci-build environment runs master's
application with each kit taken from its `ci-build` branch instead, and is the only
environment that sets `INFERNO_CI_BUILD_SUITES=true` (decided 2026-11-20, option
A-prime).

## The pieces

| Piece | Where |
| --- | --- |
| Dependency set | `Gemfile.ci-build`, `Gemfile.ci-build.lock` |
| Image build | `.github/workflows/ci-build-environment.yaml` |
| Chart values | `apps/inferno-ci-build/values.yaml` in aehrc/sparked-argo (chart: hl7au/inferno-deployment) |
| Flag | `inferno.ciBuildSuites` -> `INFERNO_CI_BUILD_SUITES` |
| Host for the radio | `inferno.ciBuildHost` -> `INFERNO_CI_BUILD_HOST`, set on staging only |
| Validator restart | `validator.restartWithAppImage` |
| Runtime config for the kit pages | `/site-config.json` (`lib/inferno_platform_template/site_config.rb`) |
| Kit page radio | `ci_build: true` suites in `web/_test_kits/*.md`, `web/_layouts/test-kit.html` |
| Argo Application, Image Updater, hostname, network policies | aehrc/sparked-argo: `apps/inferno-ci-build.yaml`, `apps/inferno-ci-build/`, `self-managed-argo/templates/inferno-ci-build-imageupdater.yaml`, `network-policies/*/ci-build-inferno.yaml`, `apps/common/networking/gateway-infra.yaml` |

## How a new CI build reaches a tester

1. A kit's nightly refresh (19:00 UTC) regenerates its suite from the IG's CI build and
   pushes the `ci-build` branch, only after its own rubocop and specs pass.
2. Every three hours, `ci-build-environment.yaml` moves only the two kits in
   `Gemfile.ci-build.lock` to their `ci-build` heads and names the image after the three
   commits it is made of: `ci-build-<app>-<au core>-<au ps>`, twelve hex characters each,
   where `<app>` is the last master commit that changed anything but `infra/`, `docs/`,
   `.github/` or Markdown (so a prod promotion or a docs change does not rebuild, or
   restart a warm validator). If ghcr already has that tag nothing changed and the run
   stops; otherwise it builds and pushes the image. A push to master that changes the
   application starts it too, and `workflow_dispatch` runs the same check on demand. There
   is no forced rebuild: new content under an existing tag is never redeployed by Image
   Updater, so to roll the environment, restart its Deployments.
3. ArgoCD Image Updater (in aehrc/sparked-argo) sees the newest `ci-build-*` tag, writes it
   to `apps/inferno-ci-build/image-values.yaml` through a pull request that
   `aiu-automerge.yaml` merges, and the `inferno-ci-build` Application rolls out.
4. The chart stamps the app image into the validator's pod template
   (`validator.restartWithAppImage`), so the validator restarts with the app. The CI-build
   suites validate against `igs '<package>#current'`, and a warm validator keeps the
   package it already loaded; a fresh one re-checks `#current` against build.fhir.org's
   manifest when it loads the package. The first validation after a refresh pays a cold
   engine build (about 50 seconds).

The commits an environment runs are in its image tag, and in the image's labels
(`au.org.hl7.inferno.ci-build.au-core-test-kit`, `au.org.hl7.inferno.ci-build.au-ps-inferno`,
and `org.opencontainers.image.revision` for the application commit). The committed lockfile is the seed, not the pin:
master needs a reviewed pull request, and a nightly bump waiting on a review would go
stale silently, which is what this design exists to prevent.

## When it fails

A failing run keeps one issue titled `CI-build environment image failing` open, assigned
to KyleOps so GitHub notifies a person, and comments on it at each further failure. The
next successful run closes it. A kit whose own refresh fails opens `CI build refresh
failing` in that kit's repository instead; the environment then keeps the last suite that
passed.

If a run's summary lists shared gems that moved away from the seed, a kit's `ci-build`
branch needs a newer shared dependency than master has locked. Relock the seed on master:

```bash
cp Gemfile.lock Gemfile.ci-build.lock
BUNDLE_GEMFILE=Gemfile.ci-build bundle lock --update au_core_test_kit au_ps_inferno --conservative
```

Then check `diff Gemfile.lock Gemfile.ci-build.lock` shows only the two kits. If bundler
moves a shared gem on the first lock (it can when a gem's source changes from rubygems to
git), set that gem back to the `Gemfile.lock` version in the seed and run `bundle lock`
again. quality-control installs the seed frozen, so a `Gemfile.common` change that is not
relocked here fails its pull request.

## The kit page radio

Each kit page lists its CI-build suite first, by its fixed id, marked `ci_build: true`.
The radio renders hidden, is never the default selection, and is shown only where it can
launch:

- **On the ci-build environment**, the app's own suite list includes it, so it launches
  locally like any other suite.
- **On staging**, `/site-config.json` names the ci-build host. The page asks that host's
  `/site-config.json` which CI-build suites it runs, and shows the radio with the title
  the kit generated (which carries the IG version) and a note that the session runs on
  another host. Create Test Session then submits inferno_core's session form route
  (`POST /suites/<suite id>`) on that host, a top-level navigation that needs no CORS and
  ends on the new session there.
- **On production** no host is set, so the radio never shows.

If the ci-build environment is down, staging shows no radio rather than one that fails.

## Running it locally

```bash
BUNDLE_GEMFILE=Gemfile.ci-build bundle install
BUNDLE_GEMFILE=Gemfile.ci-build INFERNO_CI_BUILD_SUITES=true bundle exec puma -p 4568
# a second instance standing in for staging:
INFERNO_CI_BUILD_HOST=http://localhost:4568 bundle exec puma -p 4567
```

`/site-config.json` accepts `http://localhost` as a host for exactly this; anything else
must be a bare https origin.
