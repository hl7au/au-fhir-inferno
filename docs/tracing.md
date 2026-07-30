# OpenTelemetry tracing

Both processes export spans to Alloy, which forwards to Tempo. Tracing is enabled by the
presence of `OTEL_EXPORTER_OTLP_ENDPOINT`; the Helm chart sets it, along with a distinct
`OTEL_SERVICE_NAME` per workload.

| Service | Process | Configured in | Instrumentation |
|---|---|---|---|
| `inferno-worker` | Sidekiq | `worker.rb` | Faraday, Net::HTTP, Sidekiq, plus per-test spans |
| `inferno-app` | Puma | `config.ru` | Faraday, Net::HTTP, Rack |
| `validator-api` | JVM | Helm pod annotation | OTel Java auto-instrumentation |

## Trace shape

inferno-core runs an entire test run inside one Sidekiq job, so by default a run collapses
into a single trace of tens of thousands of spans, which trace backends truncate and no UI
can render. `lib/inferno_platform_template/test_tracing.rb` therefore gives **each test its
own trace**: the test span is started with an empty parent context, so it becomes a root.

The consequence worth remembering when querying: a run is *many* traces, correlated by
`inferno.test_run_id`, not one. To select spans from other services in the same run, use a
trace-level conjunction rather than a single spanset:

```
{ span.inferno.test_run_id = "<uuid>" } && { resource.service.name = "validator-api" }
```

Run duration is the Sidekiq job span (`name = "default process"`), which the patch annotates
with the run identity so it can be found. No separate run span is emitted, because that would
duplicate a span the Sidekiq instrumentation already produces.

## Span attributes

On every test span:

| Attribute | Example | Why |
|---|---|---|
| `inferno.test_run_id` | `d266e9a6-...` | correlates the tests of one run |
| `inferno.test_session_id` | `9VcZqjUPuIr` | the last path segment of a session URL, so a user's link is enough to find their traces |
| `inferno.test_id` | `au_core_v210_draft-..._patient-..._read_test` | fully qualified test identity |
| `inferno.test_short_id` | `1.2.03` | the label the Inferno UI shows, so it matches what a user quotes |
| `inferno.test_title` | `Server returns a Patient` | readable in a table without a lookup |
| `inferno.suite_id` | `au_core_v210_draft` | aggregate by suite |
| `inferno.group_id` | `au_core_v210_draft-..._patient` | aggregate by group |
| `inferno.result` | `pass` / `fail` / `skip` / `error` | set after the test completes |

Span status is set to error **only** for `inferno.result = "error"`. A failing test is the
expected outcome of testing a non-conformant server; marking conformance failures as span
errors would pollute every error-rate panel and alert.

The Sidekiq job span carries `inferno.test_run_id`, `inferno.test_session_id` and
`inferno.suite_id`.

## Why the span name is a constant

Test spans are all named `inferno.test`. The identity lives in attributes, deliberately.

Tempo's metrics-generator uses `span_name` as a span-metrics dimension, so embedding the test
id in the name gave every test of every suite version its own metric series: 1417 of 3455
`span_name` values on the sparked cluster. Those series cannot be used, because a test emits
exactly one span per run, so each series holds a single observation and `increase()` over it
returns 0.

Collapsing the name removes that cardinality and turns `span_name="inferno.test"` into one
series that *is* useful: total test-execution time, queryable over Mimir's retention rather
than Tempo's.

Nothing is lost for querying. TraceQL filters and groups on attributes, `select()` lifts them
into table columns, and TraceQL metrics aggregate by them:

```
{ span.inferno.test_session_id = "9VcZqjUPuIr" && name = "inferno.test" }
  | select(span.inferno.test_short_id, span.inferno.test_title, span.inferno.result)

{ span.inferno.test_run_id = "<uuid>" && name = "inferno.test" }
  | quantile_over_time(duration, .95) by (span.inferno.group_id)
```

TraceQL metrics (the `| rate()` and `| quantile_over_time()` forms) are served from Tempo's
live-store and only cover roughly the **last 20 minutes**; outside that window they error
rather than return empty. Plain search covers full retention.

## Dashboards

`Inferno Run Timing` (`/d/inferno-run-timing`) is the entry point: scope it with a session id
and it answers which tests were slow and what they waited on. `Inferno Test Run Analysis`
holds the infrastructure evidence (pod CPU and memory, log-derived rates). Both live in
`aehrc/sparked-argo` under `apps/common/monitoring/manifests/`.

## Related

- [result-duration.md](./result-duration.md) - per-runnable wall time persisted on
  `results.duration_ms`, which is the number to quote to a user. Tracing is for working out
  why that number is what it is.
