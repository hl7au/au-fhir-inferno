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
  `true`), so production never lists it.

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
- A gem built from a kit's mainline carries the CI suite's code and generated metadata,
  frozen at whatever CI build the mainline held when the gem was built; only the downloaded
  package is excluded. The flag keeps it unloaded wherever it is not set.

Config, package and generated output

- `config.ci-build.json` in the repository root, with a top-level `ci_build` section:
  `package_url`, `manifest_url` and `package_date` (the date of the package the suite was
  generated from).
- Generated output goes to `lib/<kit>/generated/ci-build/`, a stable directory whatever the
  package version.
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
- Permissions: `actions`, `contents`, `issues` and `pull-requests` write. The job sets
  `GH_TOKEN` and `GH_REPO`, so the failure issue can still be opened when checkout fails.
- Opens or updates the `automated/refresh-ci-build-suite` pull request against the
  mainline, labelled `automated-pr`, with `add-paths` limited to the ci-build files (the
  `bundler-cache` gem install in `vendor/bundle` must never reach it).
- A push made with `GITHUB_TOKEN` starts no workflows, so when the pull request is created
  or updated the workflow runs `gh workflow run quality-control.yaml --ref <branch>`. The
  kit's Quality Control workflow therefore has a `workflow_dispatch` trigger. GitHub
  leaves a dispatched run's check run out of the commit's status check rollup, which is
  what a pull request's checks read, so a dispatched Quality Control run also posts a
  commit status on its commit (context `Automated Quality Control`: pending when it starts,
  then its result), which does show. It needs `statuses: write` on that job. Confirmed on
  2026-11-20: the AU PS refresh's own `GITHUB_TOKEN` dispatch put a SUCCESS status on its
  refresh pull request (hl7au/au-ps-inferno#137), and a hand dispatch did the same on AU
  Core's mainline.
- While the refresh pull request is open, every run checks it, not only runs that changed
  it: it dispatches Quality Control only when the head commit has no result yet, waits up to
  30 minutes for the status, squash-merges with `--match-head-commit` on success, and fails
  the job on a failure or a timeout. create-pull-request v8 sets `pull-request-number` and
  `pull-request-head-sha` on unchanged days too (checked in its source), which this relies
  on. After a merge it dispatches Quality Control on the mainline, because a merge made with
  `GITHUB_TOKEN` starts no push run there, and anything chained off the mainline run (AU
  Core's image build is) would otherwise never fire.
- While any run fails, scheduled or dispatched, it keeps one issue titled
  `CI build refresh failing` open, assigned to a named maintainer (KyleOps) so GitHub
  notifies a person, commenting on it at each further failure, and the next successful run
  closes it.

Runner and Ruby

- Workflows run on `ubuntu-latest` with a Ruby that ruby/ruby-builder builds for it, and
  every kit uses the same Ruby as the aggregator image. Every Ruby pin in a repository moves
  together. As of 2026-11-20 both kits are on Ruby 3.3.12 (`ubuntu-latest` is ubuntu-26.04,
  which has no Ruby 3.3.6 build); the aggregator moves to `ruby:3.3.12-slim-trixie` in
  hl7au/au-fhir-inferno#220 and is on 3.3.6 until it merges.
- Pinning `runs-on` to an older image is allowed only as a dated interim, with a comment
  naming the change that lifts it.
- A kit's Dockerfile is a development image: it matches the aggregator's Ruby version, but
  its base flavour (full or slim) may differ.
- `inferno_suite_generator` at `9aff974c` is the first revision allowing Ruby beyond
  3.3.6. Its gemspec allows Ruby `>= 3.3.6, < 3.4` (so 3.4 is closed too) and pins
  `inferno_core` to exactly 1.4.4 (added in `c6d1a90a`, generator #50), so whatever adopts
  it stays on inferno_core 1.4.4 until the generator relaxes that pin (issue
  hl7au/inferno_suite_generator#68 asks for `~> 1.4, >= 1.4.1`). Both kits are on it; the
  aggregator moves to it in hl7au/au-fhir-inferno#220. Check the
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
- Download refuses a version that is not `-ci-build` and leaves the config untouched.
- A failed refresh restores the config.

## The aggregator side

To be designed (section 2c of the platform work). The original plan had development take
the kits by git ref, and that no longer matches how hl7au/au-fhir-inferno builds: since the
trunk cut-over (`docs/phase3-trunk-cutover.md`), every push to master builds one
released-flavour image from `Gemfile`, which pins released kit gems, and staging
(`development.inferno.sparked-fhir.com`) and production run that same image. `Gemfile.dev`
is used only for `preview`-labelled PR environments. A released kit gem published before a
kit's CI suite merged carries none, so today the CI suites have no path to staging. 2c has
to choose one, and this section records the choice once made.

Whatever it chooses, these parts hold:
- The environment that should list the CI suites sets `INFERNO_CI_BUILD_SUITES=true`
  (through a chart key and configmap entry, the way `inferno.resultDuration` maps to
  `RESULT_DURATION_ENABLED` in `infra/helm/inferno/values-*.yaml`); production never does.
- `web/_test_kits/au-ps.md` and `au-core.md` list the CI suite first, by its fixed id, with a
  title that says ci-build. The kit page hides suites the running app does not report, so an
  environment without the flag shows none.
- When a regenerated suite reaches that environment, its validator restarts.

## Merging refresh pull requests

Ruled 2026-11-20: a person merges them until the Quality Control status path is proven,
then they merge themselves. The path was proven the same day: the refresh's own
`GITHUB_TOKEN` dispatch put an "Automated Quality Control" SUCCESS status on
hl7au/au-ps-inferno#137 and on hl7au/au-fhir-core-inferno#327. The automatic merge (the
refresh workflow steps above) is in hl7au/au-ps-inferno#140 and
hl7au/au-fhir-core-inferno#328.

## Adding a kit

Follow the kit side above, including its spec list, then add the kit to the aggregator side.
Copy the workflow and rake tasks from an existing kit rather than writing new ones, so a
difference between kits is always deliberate and written down here.
