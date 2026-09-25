# Public Inferno feedback flow

The platform serves `/feedback/` from its Jekyll site. The Inferno banner
links to the page with only the session ID in a same-origin URL. The page reads
Inferno's existing session and current-results APIs, then lets the reporter
select a result or enter its test ID manually if the session has been purged.
It previews the data that will prefill a GitHub issue form in this repository.
The reporter reviews it again on GitHub and submits the public issue. The form
asks what was expected and what happened. Public issues let the community see
reports and follow their resolution; Zulip remains useful for discussion.

The public report includes the suite ID and version, test kit and version,
test ID, outcome, result time, feedback time, and a **feedback reference**.
It omits the raw session ID, run ID, result ID and full session URL. It also
omits all FHIR inputs and outputs, messages, request and response data, headers,
and tokens. The reporter must review their own text for sensitive data. The
GitHub form repeats the warning and requires acknowledgement.

## Trace correlation

The browser and the worker compute the same reference:

```
fb- + first 24 hex characters of SHA-256("au-inferno-feedback:v1:" + session_id)
```

Inferno Core generates session IDs from 64 random bits. This one-way reference
lets maintainers search Grafana/Tempo for `inferno.feedback_ref` without making
the session URL reconstructable from the public issue. The worker adds it to
per-test, persistence and Sidekiq run spans alongside the existing private
`inferno.test_session_id`, `inferno.test_run_id` and `inferno.test_id` attributes.
Search by feedback reference, then narrow by test ID and result time. Per-test
spans are separate traces. A reference works only for traces created after this
instrumentation is deployed and while Tempo retains them. Session rows may be
purged independently; the public issue remains useful as a problem report.

The client reads Inferno's result response, which can contain inputs, outputs,
messages and request summaries, but uses only the allowlisted scalar fields.
No report is stored by this application. A GitHub account is needed to submit
an issue. If the URL-prefilled issue form fails to carry fields across, the
page provides a copy button and a plain link to the form.

For community visibility to mean something, maintainers should acknowledge a
new report in the public issue, reproduce or explain the result, link any
follow-up kit issue or change, and close with the outcome and released version.
When a report needs private evidence, ask for that through a separate private
channel while keeping the public issue free of test data. Zulip can host the
early discussion; link its public topic from the issue when it informs the fix.

## Local extension pattern and upstream improvement

This repository already uses `Module#prepend` patches around Inferno Core
behaviour and tests them in `spec/inferno_deployment`. The tracing patch is the
smallest such extension for correlation. Those Ruby patches cannot add a
stable action beside each result in Inferno Core's React UI; injecting controls
into its DOM from the banner would depend on private markup.

A narrow Inferno Core extension would expose an optional result action URL
callback. Core would render “Report this result” beside each result and pass
only the session and result IDs to the platform's same-origin feedback page.
The page would resolve the result and prepare the same public preview, without
putting raw IDs or test data in the GitHub issue. The current banner link and
result selector work without that change.
