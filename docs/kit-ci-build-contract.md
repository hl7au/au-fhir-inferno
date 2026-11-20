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
  touches gem publishing, and the development aggregator takes the kits by git ref.

## The kit side

`<kit>` is the kit's lib directory (`au_ps_inferno`, `au_core_test_kit`) and `<ns>` its rake
namespace (`au_ps`, `au_core`).

Suite and registration

- The CI build is a suite version with the key `ci-build`.
- Its suite id is fixed: `au_ps_ci_build`, `au_core_ci_build`, and `<prefix>_ci_build` for a
  new kit.
- Its title shows the package version and says it tracks the CI build, not a release:
  `AU PS 1.1.0-ci-build Test Suite (tracks the CI build)`,
  `AU Core v3.0.0-ci-build (tracks the CI build)`. Its description says a regeneration can
  stop earlier sessions rendering.
- `lib/<kit>.rb` requires it only when `ENV['INFERNO_CI_BUILD_SUITES'] == 'true'` (exactly
  `true`), so production never lists it. A gem built from the mainline does carry the CI
  suite's code and generated metadata, frozen at whatever CI build the mainline held when
  it was built; only the downloaded package is excluded.

Validation

- The validator gets `igs '<package id>#current'`, a package id, never a file path. The
  HL7 validator's package cache re-checks `#current` against build.fhir.org's
  `package.manifest.json` when it loads the package (from the platform roadmap's research,
  not re-checked since). A warm validator session keeps the package it already loaded, so
  the deployment's validator restarts when a regenerated suite reaches it (see the
  aggregator side).
- Profile canonicals in the CI suite are unversioned, because a validator following
  `#current` can hold a newer package than the suite was generated from. AU PS does this.
  AU Core still pins `|<package version>` until the generator can emit unversioned
  references (hl7au/inferno_suite_generator#52); that is a tracked gap, not a variant.

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
- While any run fails, scheduled or dispatched, it keeps one issue titled
  `CI build refresh failing` open, assigned to KyleOps so GitHub notifies a person,
  commenting on it at each further failure, and the next successful run closes it.

Runner and Ruby

- Workflows run on `ubuntu-latest` with a Ruby that ruby/ruby-builder builds for it.
  Today that is Ruby 3.3.12 across the aggregator and every kit: `ubuntu-latest` is
  ubuntu-26.04, which has no Ruby 3.3.6 build, and 3.3.12 matches the aggregator image
  (`ruby:3.3.12-slim-trixie`). Every Ruby pin in a repository moves together.
- Pinning `runs-on` to an older image is allowed only as a dated interim, with a comment
  naming the change that lifts it.
- A kit's Dockerfile is a development image: it matches the aggregator's Ruby version, but
  its base flavour (full or slim) may differ.
- `inferno_suite_generator` at `9aff974c` is the first revision allowing Ruby beyond
  3.3.6. Its gemspec allows Ruby `>= 3.3.6, < 3.4` (so 3.4 is closed too) and pins
  `inferno_core` to exactly 1.4.4 (added in `c6d1a90a`, generator #50), so every kit and
  the aggregator stay on inferno_core 1.4.4 until the generator relaxes that pin
  (hl7au/inferno_suite_generator#68 proposes `~> 1.4, >= 1.4.1`). Check the
  gemspec at whatever revision you adopt. Move a kit to a new revision by editing the git
  revision and relocking, not by a broad `bundle update`, so no unrelated gem moves.

Specs each kit carries

- Without `INFERNO_CI_BUILD_SUITES=true` the CI suite is absent at boot.
- With the flag it registers under the fixed id. This is tested by booting Inferno in a
  child process, because requiring a suite file after boot does not register its tests.
- Its validator `igs` is exactly `<package id>#current`.
- Its title starts with the version recorded in `config.ci-build.json`.
- No generated file carries a version-derived id.
- Download refuses a version that is not `-ci-build` and leaves the config untouched.
- A failed refresh restores the config.

## The aggregator side

Not built yet (roadmap section 2c).

- `values-dev.yaml` sets `INFERNO_CI_BUILD_SUITES=true`; production never does.
- `web/_test_kits/<kit>.md` lists the CI suite first, by its fixed id, with a title that
  says ci-build. The kit page hides suites the running app does not report, so production
  shows none.
- Dev takes the kits by git ref in `Gemfile.dev.lock`. A scheduled workflow bumps those refs
  and opens a pull request, because Dependabot does not track git-ref Bundler sources
  reliably.
- When a regenerated suite reaches dev, the dev validator restarts, so its in-memory
  session drops the previously loaded `#current` IG (a warm session never re-checks it).

## Where each kit stands

Checked 2026-11-20.

| | AU PS | AU Core |
| --- | --- | --- |
| Suite, config, tasks, workflow | merged (#135, #136) | merged (hl7au/au-fhir-core-inferno#324) |
| Quality Control by dispatch, failure issue | merged (#139) | merged (#324); assignee in #326 |
| Ruby 3.3.12 | merged (#138) | hl7au/au-fhir-core-inferno#326, open |
| Unversioned canonicals | yes | gap, inferno_suite_generator#52 |

## Merging refresh pull requests

Ruled 2026-11-20: a person merges them for now, and they merge themselves once the
Quality Control status path is proven. With no app, an automatic merge has to be made with
`GITHUB_TOKEN` by the refresh workflow after it waits on the dispatched run, and a merge
made that way starts no push workflows on the mainline.

## Adding a kit

Follow the kit side above, including its spec list, then add the kit to the aggregator side
and to the table. Copy the workflow and rake tasks from an existing kit rather than writing
new ones, so a difference between kits is always deliberate and written down here.
