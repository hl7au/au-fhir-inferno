# Running the AU Core test kit in your CI

This folder is a recipe a FHIR server developer copies into their own repository to run
the HL7 AU Core test kit against their server on every pull request or every night, and
to fail the build when a test that was fine before now fails or errors.

It runs everything inside the CI job: your server, the HL7 AU test data, and a private
Inferno with its own FHIR validator, from the same image that serves
[inferno.hl7.org.au](https://inferno.hl7.org.au). Nothing is sent to the hosted Inferno or
its validator, and no results leave your job.

The results tell you what changed between two runs of your own server. They are not an
assessment by HL7 Australia or Sparked, and a clean run is not a statement that a server
meets AU Core.

| File | What it does |
| --- | --- |
| [`compose.yaml`](compose.yaml) | Starts your FHIR server (a placeholder you replace), Inferno, its worker, the validator, PostgreSQL and Redis |
| [`load_test_data.py`](load_test_data.py) | Writes the AU Core test data from [hl7au/au-fhir-test-data](https://github.com/hl7au/au-fhir-test-data) to your server in reference order |
| [`run_inferno.py`](run_inferno.py) | Runs a test suite through the Inferno JSON API and compares the results with your baseline |
| [`example-workflow.yml`](example-workflow.yml) | A GitHub Actions workflow that does all of the above |

The two scripts need Python 3.9 or later and nothing outside the standard library. Any
CI system that can run Docker Compose and Python can use them; the workflow is the
GitHub Actions version.

## Set it up

1. Copy `compose.yaml`, `load_test_data.py` and `run_inferno.py` to `.github/inferno/`
   in your repository, and `example-workflow.yml` to
   `.github/workflows/au-core-inferno.yml`.
2. In `compose.yaml`, replace the `fhir-server` service (a HAPI FHIR reference server)
   with your own server: your image, or a `build:` of your repository. Keep the service
   name `fhir-server` and port 8080, or change the URLs in the workflow to match. If
   your server takes a while to start, the loader waits up to five minutes for
   `[base]/metadata` to answer.
3. If your server needs authentication, store the token as a repository secret and give
   it to both scripts (see [Authentication](#authentication)).
4. Run the workflow once by hand (Actions, AU Core Inferno, Run workflow) with **Record
   this run as the baseline** ticked. Download `baseline-au_core_v200.json` from the
   run's `inferno-results` artifact, look through it, and commit it to
   `.github/inferno/`.
5. From then on, every run compares with that file.

## What a run does

1. **Starts the stack.** `docker compose up --wait` starts your server and Inferno and
   waits until Inferno's API and the validator answer.
2. **Loads the test data.** The workflow checks out a tagged release of
   hl7au/au-fhir-test-data and `load_test_data.py` writes its `au-core` folder to your
   server (1,403 resources in release v2.0.0, plus one Patient that an AU Core Encounter
   references from the `au-erequesting` folder).
3. **Runs the suite.** `run_inferno.py` creates an Inferno test session, starts a run of
   the whole suite with your server's URL, waits for it to finish and reads every result.
4. **Compares with your baseline** and fails the job if there is a regression.
5. **Keeps the results.** The raw results (`inferno-results.json`) are uploaded as an
   artifact, and a summary table goes on the run's summary page. If a step fails, the
   container logs are printed.

On a GitHub-hosted runner the first run downloads the images and the validator downloads
the AU Core packages, so expect it to take longer than later runs.

## Loading the test data

`load_test_data.py` reads every JSON resource under the paths it is given and writes
each with `PUT [base]/[type]/[id]`, so resources keep the ids the test kit expects and a
rerun updates them in place instead of adding copies.

Servers that check references on write reject a resource whose references do not exist
yet, so the loader works out which resources reference which and writes a resource only
after everything it references. Some resources reference each other in a cycle (in the
AU Core data, three Patients and their RelatedPersons); no order of single writes
satisfies a cycle, so the loader writes each cycle as one `transaction` Bundle of `PUT`
entries. Writes that do not depend on each other go in parallel (`--workers`, default 4).

`--resolve-from DIR` adds any resource the load set references but does not contain,
found anywhere under `DIR`. A reference that cannot be found is printed as a warning and
the loader still tries the write. The loader exits non-zero if any write fails, with the
server's OperationOutcome for each failure.

Your server needs to accept `PUT` to an id that does not exist yet (update as create).
If it assigns its own ids instead, the suite's default `patient_ids` and other id inputs
will not match; give the ids your server assigned with `--input`.

Run `python3 load_test_data.py --help` for every option, and `--dry-run` to print the
write order without writing anything.

## Running the suite

`run_inferno.py` uses the same JSON API the Inferno web page uses, under
`/suites/api` on this image:

| Call | Used for |
| --- | --- |
| `GET /suites/api/test_suites/{suite}` | Waits for Inferno to be ready; reads the suite's inputs, their defaults, and the group and test titles |
| `POST /suites/api/test_sessions` | Creates a session for the suite |
| `POST /suites/api/test_runs` | Starts a run of the whole suite with the inputs |
| `GET /suites/api/test_runs/{id}` | Polls until the run's status is `done` |
| `GET /suites/api/test_sessions/{id}/results` | Reads every group and test result |

Inputs you do not give keep the suite's defaults. For AU Core those defaults are the
patient, practitioner, organisation and other ids from the test data, so the only input
the workflow sets is `url`. Inferno runs inside the compose network, so `url` is
`http://fhir-server:8080/fhir` (the service name), while the loader on the runner uses
`http://localhost:8080/fhir`.

To run a different suite, change `SUITE` in the workflow and the baseline file name. The
suite ids the image offers are listed at `GET http://localhost:4567/suites/api/test_suites`
(or on the hosted instance at <https://inferno.hl7.org.au/suites/api/test_suites>):
`au_core_v100`, `au_core_v200`, `au_core_v210_draft` and `au_core_v300_ballot1` in
image v1.2.2. Use the test data release that matches the AU Core version you build to.
A suite that stops to wait for a person (a SMART App Launch login, for example) cannot
run in CI; the script stops with an error if a run ends waiting.

The validator in the stack checks codes against the public HL7 AU development
terminology server, `https://tx.dev.hl7.org.au/fhir`, the same one the hosted Inferno
uses, so the job needs outbound internet access. If that server is unreachable,
validation tests error and show up as regressions; run the job again.

### Authentication

Both scripts take credentials for your server. Keep the value in a repository secret,
expose it to the step as an environment variable, and add:

- to the loader: `--header "Authorization: Bearer $SERVER_TOKEN"`
- to the suite: `--input header_name=Authorization --input "header_value=Bearer $SERVER_TOKEN"`

The runner prints the names of the inputs it was given, never their values.

## What counts as a regression

Every test ends with one of Inferno's result codes, such as `fail`, `error`, `skip` or
`omit`. The baseline is a JSON file that records the result code of every test from a
run you chose:

```json
{
  "suite": "au_core_v200",
  "suite_version": "1.4.6",
  "results": {
    "au_core_v200-au_core_v200_fhir_api-au_core_v200_patient-au_core_v200_patient_patient_read_test": "<result code>",
    "...": "..."
  }
}
```

A **regression** is a test whose result in this run is `fail` or `error`, and whose
result in the baseline is anything else or is missing. Each regression is listed with
its test number, title and Inferno's message, and the job fails (exit code 1).

Nothing else fails the job on its own:

- A test that failed or errored in the baseline and still does is not a regression.
- A test that moves to `skip` or `omit` is not a regression.
- A test that failed or errored in the baseline and no longer does is listed as fixed.
  Record a new baseline to hold on to the improvement.
- A test the baseline does not list (after the kit adds tests) is a regression only if
  it fails or errors.

The job also fails (exit code 2) when the run cannot finish: Inferno does not start,
the suite id is unknown, the run is still going after `--timeout` seconds (default
3600), or the run produced no results.

Record a new baseline whenever you mean to accept the current results: after you fix
something, and after you update the Inferno image or the test data release, because new
kit versions and new data change which tests run and what they check. Run the workflow
by hand with **Record this run as the baseline** ticked, or locally:

```sh
python3 .github/inferno/run_inferno.py --suite au_core_v200 \
  --input url=http://fhir-server:8080/fhir \
  --write-baseline .github/inferno/baseline-au_core_v200.json
```

## Running it on your machine

The same commands work locally with Docker and Python. From the folder that holds the
three files:

```sh
git clone --depth 1 --branch v2.0.0 https://github.com/hl7au/au-fhir-test-data.git
docker compose up --detach --wait --wait-timeout 900
python3 load_test_data.py --base-url http://localhost:8080/fhir \
  --resolve-from au-fhir-test-data/au-fhir-test-data-set \
  au-fhir-test-data/au-fhir-test-data-set/au-core
python3 run_inferno.py --suite au_core_v200 --input url=http://fhir-server:8080/fhir \
  --write-baseline baseline-au_core_v200.json
docker compose down --volumes
```

If port 8080 or 4567 is taken, set `FHIR_SERVER_PORT` or `INFERNO_PORT` for
`docker compose`, then give the loader the matching `--base-url` and the runner the
matching `--inferno` (or set `INFERNO_URL`, for example `http://localhost:14567/suites`). The Inferno and validator
images are built for amd64 only; on an Apple silicon Mac Docker runs them under
emulation, which works but is slower. While a run is going, the Inferno web page at
<http://localhost:4567> shows the session.

The stack peaked at about 6 GB of memory in testing, most of it the validator (its Java
heap is capped at 4 GB in `compose.yaml`); give Docker at least 8 GB.

## Versions and how to move them

Every image is pinned to a tag and its digest, and every action to a commit, so a run
today and a run next month use the same software unless you change it.

| What | Pinned to | Where to look for a newer one |
| --- | --- | --- |
| Inferno (`ghcr.io/hl7au/au-fhir-inferno`) | `v1.2.2`, the release hosted at inferno.hl7.org.au | [Releases](https://github.com/hl7au/au-fhir-inferno/releases) |
| Validator (`markiantorno/validator-wrapper`) | `1.0.78`, held on purpose (below) | Keep in step with `validatorImageUri` in [`infra/helm/inferno/values-prod.yaml`](../../infra/helm/inferno/values-prod.yaml) |
| Test data (`hl7au/au-fhir-test-data`) | `v2.0.0` | [Releases](https://github.com/hl7au/au-fhir-test-data/releases) |
| PostgreSQL, Redis | `postgres:19.0-alpine`, `redis:8.10.3-alpine` | Docker Hub |
| HAPI FHIR (placeholder only) | `hapiproject/hapi:v8.12.0-2` | Replaced by your server |
| `actions/checkout`, `actions/upload-artifact` | `v7.0.1`, `v7.0.2` | Their GitHub releases |

The validator is held at 1.0.78 because the hosted Inferno runs that version: from
1.0.79 the validator stops using server-side terminology caching against Ontoserver,
which `tx.dev.hl7.org.au` runs, and validation takes about twice as long
([details](../issues/validator-wrapper-1079-terminology-regression.md)). Results are the
same either way, so moving it only costs time.

To update an image, change the tag and replace the digest with the one
`docker buildx imagetools inspect <image>:<tag>` prints for the whole image (the
`Digest:` line at the top, not a per-platform one). Dependabot can do this, and the
action pins, for you:

```yaml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    schedule: { interval: weekly }
  - package-ecosystem: docker-compose
    directories: [/.github/inferno]
    schedule: { interval: weekly }
```

Dependabot will also offer validator updates; decline them unless the hosted Inferno has
moved. After any version change, record a new baseline in the same pull request, so the
change in results is reviewed with the change that caused it.
