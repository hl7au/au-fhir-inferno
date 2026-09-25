# Public Inferno feedback flow

The platform serves `/feedback/` from its Jekyll site. The AU suite footer
passes only the session ID in a same-origin URL. An expanded result also has a
small local action that passes its test and result IDs and preselects that exact
result. The page reads Inferno's session and results APIs, lets
reporters search by test number or title, and supports manual entry after a
session is purged. The reporter reviews the exact public context before posting.
Anonymous is the default; a reporter may instead choose to publish a name or
contact email. Both modes create a public GitHub issue through the same-origin
intake, without a GitHub account. A prefilled GitHub issue draft remains a fallback.
Public issues let the community follow resolution; Zulip remains useful for
discussion.

The public report includes the suite ID and version, test kit and version,
test ID, outcome, result time, feedback time, and a **feedback reference**.
It omits the raw session ID, run ID, result ID and full session URL. It also
omits all FHIR inputs and outputs, messages, request and response data, headers,
and tokens. The server also rejects full session URLs and the current session
ID in free text. The reporter must review their own text for sensitive data;
optional contact details are public only after an explicit choice and consent.
The GitHub fallback opens a prefilled title and body after the reporter reviews
the draft on this site. The issue editor requires GitHub sign-in.

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
messages and request summaries, but keeps only allowlisted scalar fields. Test
numbers and titles come from suite metadata. Failed and errored results appear
first in the picker. The server rebuilds the public context from typed fields
and computes the feedback reference itself; a preview endpoint returns the
same fields shown to the reporter. No report is stored by this application.
If account-free intake is unavailable, the page offers a copy button and a
GitHub issue-editor link; that fallback requires GitHub sign-in. The link uses
GitHub's standard title and body parameters because issue forms on this branch
do not become available to GitHub until they reach the default branch.

## Account-free intake configuration

The web pod needs a dedicated fine-grained repository token with **Issues:
write** for `hl7au/au-fhir-inferno`. Put it in a Kubernetes Secret named
`inferno-feedback-github`, under the key `token`, in each environment's
namespace. Restart `inferno-app` after first provisioning. Do not put the
token in chart values, the image, browser code, or issue text. In dev/prod,
the existing AWS Secrets Manager integration can instead sync a JSON secret
with a `token` property: set `externalSecrets.feedbackSecretArn` to its name or
ARN and give the External Secrets role read access. Do not place a GitHub
credential in pull request preview namespaces, which run PR supplied chart and
application code. Without the Secret, the account-free button stays hidden and
the GitHub fallback remains available.

The intake validates typed fields and same-origin requests, caps request size,
uses a bot trap, and applies Redis-backed limits of 20 reports per IP and 100
overall per hour. Redis or GitHub failures fail closed without logging the
report body. The GitHub API identity will appear as the issue author; the
issue body states whether the reporter chose anonymous or public attribution.
These simple controls favour low friction. Monitor abuse and add a silent
challenge only if the limits prove insufficient.

For community visibility to mean something, maintainers should acknowledge a
new report in the public issue, reproduce or explain the result, link any
follow-up kit issue or change, and close with the outcome and released version.
When a report needs private evidence, ask for that through a separate private
channel while keeping the public issue free of test data. Zulip can host the
early discussion; link its public topic from the issue when it informs the fix.

## Local extension pattern and upstream improvement

The result action is a small adapter loaded by the platform banner. It attaches
to Inferno Core 1.4.3's `data-testid="...-detail"` element when a test expands,
outside the test kit gems and without a UI fork. It passes only the session and
test/result IDs to the same-origin page; no message text or FHIR data is copied. This
is a private DOM detail, so the suite footer link and searchable picker remain
the supported fallback if Core changes its markup. Browser preview checks and
an upgrade check are required when bumping Inferno Core.

A narrow upstream extension would expose an optional result action URL callback
on a suite. Core would render “Give feedback on this result” beside each result
and pass the session and result IDs to the platform's same-origin page. That
would replace the DOM adapter with a supported contract. Message-level hooks can follow only if there is a clear
need; messages can contain resource identifiers and must never be copied into
a public report automatically.
