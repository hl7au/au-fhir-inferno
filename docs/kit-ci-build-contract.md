# Kit CI-build suite contract

What a test kit does so the development aggregator can offer a suite that tracks its IG's
CI build on build.fhir.org, listed above the released suites on the kit page. Production
never loads it. The AU PS kit (hl7au/au-ps-inferno) and the AU Core kit
(hl7au/au-fhir-core-inferno) both follow this contract; a new kit should too, and a change
to the pattern starts here and then reaches every kit.

This file stands alone: it is the checklist each kit is held to, and the rulings it rests
on are listed below.

## Rulings this rests on

- The CI suite is an extra suite version inside the kit gem, not a separate Inferno
  instance.
- The suite id is fixed and does not follow the package version. The version a person sees
  always comes from the IG package and is never ahead of it; a regeneration at the same IG
  version replaces the suite in place, and losing old ci-build sessions on dev is accepted.
- Nothing depends on a GitHub App or on hl7au organisation admin (2026-11-20).
- Kit gems are not published until the full team signs off, so nothing here automates or
  touches gem publishing.
- The generated CI suite lives only on a `ci-build` branch in each kit, which the daily
  refresh updates directly; there are no refresh pull requests, and the kit's mainline
  carries the tooling but no CI suite (2026-11-21). The repository only ever holds one CI
  build: a new CI build replaces the old one in place.
- Testers reach the CI suites through a permanent ci-build environment that takes each kit
  from its `ci-build` branch, launched from a radio on development.inferno's kit page
  (2026-11-20, option A-prime).

## The kit side

`<kit>` is the kit's lib directory (`au_ps_inferno`, `au_core_test_kit`) and `<ns>` its rake
namespace (`au_ps`, `au_core`).

Suite and registration

- The CI build is a suite version with the key `ci-build`.
- Its suite id is fixed: `au_ps_ci_build`, `au_core_ci_build`, and `<prefix>_ci_build` for a
  new kit.
- Its title shows the package version and says it tracks the CI build, not a release:
  `AU PS <version> Test Suite (tracks the CI build)`,
  `AU Core v<version> (tracks the CI build)`, where `<version>` is the package version
  recorded in `config.ci-build.json` (for example `1.0.1-ci-build`). Its description says
  a regeneration can stop earlier sessions rendering.
- `lib/<kit>.rb` requires it only when `ENV['INFERNO_CI_BUILD_SUITES'] == 'true'` (exactly
  `true`) and the suite file exists, so production never lists it and the mainline, which
  has no CI suite, loads cleanly.

Validation

- The validator gets `igs '<package id>#current'`, a package id, never a file path. The
  HL7 validator's package cache re-checks `#current` against build.fhir.org's
  `package.manifest.json` when it loads the package, and a warm validator session keeps the
  package it already loaded, so the deployment's validator restarts when a regenerated suite
  reaches it. Both come from research done when this design was planned and have not been
  re-checked since.
- Profile canonicals in the CI suite are unversioned, because a validator following
  `#current` can hold a newer package than the suite was generated from. AU PS does this.
  AU Core still pins `|<package version>` until the generator can emit unversioned
  references (hl7au/inferno_suite_generator#52); that is a tracked gap, not a variant.
- A gem built from a kit's mainline carries no CI suite, because the mainline has none.

Branch, config, package and generated output

- The mainline holds the tooling: `config.ci-build.json` in the repository root (with a
  top-level `ci_build` section: `package_url`, `manifest_url` and `package_date`), the rake
  tasks, the refresh workflow, the flag check and the specs. Its `config.ci-build.json`
  values are only a starting point.
- The `ci-build` branch is the mainline plus the generated suite: the generated output in
  `lib/<kit>/generated/ci-build/` (a stable directory whatever the package version), any
  suite file the kit generates outside it (AU PS writes
  `lib/au_ps_inferno/suite/au_ps_ci_build.rb` from a template on the mainline), and its own
  `config.ci-build.json` recording the package the suite was generated from.
- The package is a local download at `lib/<kit>/igs/ci-build.tgz`. It is listed in
  `.gitignore` and `.dockerignore` and excluded from the gemspec's files.

Rake tasks

- `<ns>:ci_build:check` reports whether the manifest date differs from `package_date`.
- `<ns>:ci_build:download` fetches `package.tgz` and records the version and date from the
  package's own `package.json`, so a CI build landing between two requests cannot put the
  config out of step. It refuses a package whose version does not end in `-ci-build`.
- `<ns>:ci_build:refresh[force]` regenerates only the ci-build version when the date
  changed, or always with `force`, and puts the config back if generation fails.
- `<ns>:generate[ci-build]` never downloads: it refuses a missing package, or a local
  package the config does not describe, so only download and refresh change what the suite
  tracks. A plain `<ns>:generate` never regenerates the CI build.
- `make generate_ci_build` runs the forced refresh.

Refresh workflow (`.github/workflows/refresh-ci-build-suite.yaml`)

- Runs daily at 19:00 UTC (early morning in eastern Australia) and on `workflow_dispatch`
  with a boolean `force` input; one concurrency group, `refresh-ci-build-suite`, with no
  cancelling.
- Checks out `ci-build` (creating it from the mainline if absent) and runs
  `git merge --no-edit origin/<mainline>`. It never resolves a conflict: a conflict fails
  the job, and a person merges the mainline into `ci-build` by hand once. A mainline edit to
  `config.ci-build.json` is the likely cause, since its recorded date sits beside the URLs.
- Regenerates when the CI build's `package.manifest.json` date differs from the date
  recorded on the branch, when the merge brought in new mainline commits (so a generator
  change reaches the suite), or when forced.
- Runs the kit's rubocop and unit specs on the merged, regenerated tree, and pushes to
  `ci-build` only if they pass, so the branch is always green for whatever pins it. It never
  force-pushes: the ci-build environment pins a commit on this branch, and a force-push
  would orphan it. The branch's history accumulates generated diffs; the mainline never sees
  them.
- The job sets `GH_TOKEN` and `GH_REPO`, so the failure issue can still be opened when
  checkout fails. While any run fails, scheduled or dispatched, it keeps one issue titled
  `CI build refresh failing` open, assigned to a named maintainer (KyleOps) so GitHub
  notifies a person, commenting on it at each further failure, and the next successful run
  closes it.
- The kit's Quality Control workflow runs on push as usual; the refresh does its own gate
  because a push made with `GITHUB_TOKEN` starts no workflows.

Runner and Ruby

- Workflows run on `ubuntu-latest` with a Ruby that ruby/ruby-builder builds for it, and
  every kit uses the same Ruby as the aggregator image. Every Ruby pin in a repository moves
  together. As of 2026-11-20 both kits are on Ruby 3.3.12 (`ubuntu-latest` is ubuntu-26.04,
  which has no Ruby 3.3.6 build); the aggregator moved to `ruby:3.3.12-slim-trixie` in
  hl7au/au-fhir-inferno#220.
- Pinning `runs-on` to an older image is allowed only as a dated interim, with a comment
  naming the change that lifts it.
- A kit's Dockerfile is a development image: it matches the aggregator's Ruby version, but
  its base flavour (full or slim) may differ.
- `inferno_suite_generator` at `9aff974c` is the first revision allowing Ruby beyond
  3.3.6. Its gemspec allows Ruby `>= 3.3.6, < 3.4` (so 3.4 is closed too) and pins
  `inferno_core` to exactly 1.4.4 (added in `c6d1a90a`, generator #50), so whatever adopts
  it stays on inferno_core 1.4.4 until the generator relaxes that pin (issue
  hl7au/inferno_suite_generator#68 asks for `~> 1.4, >= 1.4.1`). Both kits are on it; the
  aggregator moved to it in hl7au/au-fhir-inferno#220. Check the
  gemspec at whatever revision you adopt. Move a kit to a new revision by editing the git
  revision and relocking, not by a broad `bundle update`, so no unrelated gem moves.

Specs each kit carries

- Without `INFERNO_CI_BUILD_SUITES=true` the CI suite is absent at boot.
- With the flag it registers under the fixed id. This is tested by booting Inferno in a
  child process, because requiring a suite file after boot does not register its tests.
- Its validator `igs` is exactly `<package id>#current`.
- Its title starts with the kit name and the version recorded in `config.ci-build.json`.
- Where the kit generates Ruby for the CI suite (AU Core), no generated file carries a
  version-derived id. A kit that generates only metadata (AU PS) instead checks its fixed
  id and that it shares no id with a released suite.
- Specs that need the generated suite skip when it is absent, so they run on `ci-build`
  and in the refresh job; the tooling specs run everywhere.
- Download refuses a version that is not `-ci-build` and leaves the config untouched.
- A failed refresh restores the config.

## The aggregator side

Since the trunk cut-over (`docs/phase3-trunk-cutover.md`), every push to master builds one
released-flavour image from `Gemfile`, and staging (`development.inferno.sparked-fhir.com`)
and production run that same image, so the CI suites cannot live in it. Decided 2026-11-20
(option A-prime), built in section 2c of the platform work and described in full in
`docs/ci-build-environment.md`:

- A permanent ci-build environment, built from `Gemfile.ci-build`, which takes each kit
  from its `ci-build` branch (for example
  `gem 'au_core_test_kit', github: 'hl7au/au-fhir-core-inferno', branch: 'ci-build'`),
  and the only environment with `INFERNO_CI_BUILD_SUITES=true` (chart key
  `inferno.ciBuildSuites`, configmap entry and schema, the way `inferno.resultDuration`
  maps to `RESULT_DURATION_ENABLED`). Its values are
  `apps/inferno-ci-build/values.yaml` in aehrc/sparked-argo; its Argo Application, Image Updater and
  hostname live in aehrc/sparked-argo. Staging and production keep one tested image and
  never set the flag.
- `Gemfile.ci-build.lock` on master is the seed: every shared gem matches `Gemfile.lock`
  and quality-control installs it frozen. The deployed pin is the image tag,
  `ci-build-<app>-<au core>-<au ps>` (twelve hex characters each; `<app>` is the last
  master commit that changed the application), also recorded in the image's labels,
  because master needs a reviewed pull request and a nightly bump waiting on review would
  go stale silently.
- `.github/workflows/ci-build-environment.yaml` runs every three hours, on a master
  push that changes the application, and on `workflow_dispatch`. It moves only the two
  kits in the lock to their `ci-build` heads, and builds and pushes the image when ghcr
  has no image of that name yet. ArgoCD Image Updater deploys the newest
  `ci-build-*` tag. While the workflow fails it keeps one issue titled
  `CI-build environment image failing` open, assigned to KyleOps; the next success closes
  it.
- The validator restarts with every new image: `validator.restartWithAppImage` stamps the
  app image into the validator's pod template, so a regenerated suite always meets a
  validator that reloads `#current`.
- `web/_test_kits/au-ps.md` and `au-core.md` list the CI suite first, by its fixed id,
  marked `ci_build: true`. It renders hidden and is never the default selection. On the
  ci-build environment it launches locally. On staging, `inferno.ciBuildHost`
  (`INFERNO_CI_BUILD_HOST`, served to the page by `/site-config.json`) names the ci-build
  host; the page shows the radio only when that host's `/site-config.json` lists the
  suite, labels it with the suite title the kit generated, says the session runs on
  another host, and launches through inferno_core's session form route there. Production
  sets no host and never shows it.

## Adding a kit

Follow the kit side above, including its spec list, then add the kit to the aggregator side.
Copy the workflow and rake tasks from an existing kit rather than writing new ones, so a
difference between kits is always deliberate and written down here.
