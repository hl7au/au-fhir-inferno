# Inferno Performance Tracking

Technical reference for the per-session performance tracking system built into this Inferno instance.

## What It Tracks

Every test session records two categories of external call time:

| Category | What's measured | Table |
|---|---|---|
| **FHIR server** | HTTP round-trip time for outgoing requests to the FHIR under test | `requests` (existing) |
| **Validator** | Wall-clock time for each `resource_is_valid?` call to the validator API | `validator_timing` (new) |

Session timing (start, end, duration) is derived from the `test_sessions` and `results` tables — no additional writes needed.

## Components

### `lib/inferno_platform_template/request_timing.rb`

Patches `Inferno::Utils::Middleware::RequestLogger` to record `duration_ms` on every request row. The `requests` table already stores outgoing FHIR server calls; this adds timing so the performance page can sum them per session.

### `lib/inferno_platform_template/validator_timing.rb`

Prepends `InfernoPlatformTemplate::ValidatorTimingPatch` into `Inferno::DSL::FHIRValidation`. The patch wraps `resource_is_valid?` using Ruby's `...` forwarding so argument defaults (notably `resource: self.resource`) continue to be evaluated in the test instance's context via `super`.

Each call writes one row to `validator_timing`:

```
id              UUID
test_session_id Session ID (from test instance)
validator_url   ENV['FHIR_RESOURCE_VALIDATOR_URL'] (defaults to http://validator-api:3500)
duration_ms     Wall-clock milliseconds (Process::CLOCK_MONOTONIC)
created_at      UTC timestamp
```

The table is separate from `requests` to avoid the foreign-key constraint on `result_id` — validator calls happen inside tests but are not 1:1 with individual HTTP request records.

Errors are silently swallowed so timing failures never affect test execution.

### `db/migrate/002_add_validator_timing.rb`

Creates the `validator_timing` table with an index on `test_session_id`.

### `lib/inferno_platform_template/performance_app.rb`

Sinatra app mounted at `/performance` (HTML dashboard) and `/api/performance` (JSON API) via `Rack::URLMap` in `config.ru`.

**API endpoint**: `GET /api/performance/test_sessions/:session_id`

Response shape:

```json
{
  "session_id": "...",
  "session_started_at": "2026-06-04T05:19:08Z",
  "session_ended_at":   "2026-06-04T05:25:32Z",
  "session_duration_ms": 344000,
  "summary": {
    "fhir_count":      659,
    "fhir_ms":         56176,
    "fhir_mean_ms":    85,
    "fhir_median_ms":  72,
    "fhir_max_ms":     1843,
    "validator_count": 111,
    "validator_ms":    109939,
    "validator_mean_ms": 990,
    "by_group": [
      {
        "group": "capability_statement",
        "count": 3,
        "total_ms": 110042,
        "tests": [...]
      }
    ]
  },
  "requests": [...]
}
```

**`by_group` computation**: Test IDs use dash-separated segments (`suite-group-test`). The group is extracted as `parts[1..-2].join('-')`, giving a section-level breakdown of where FHIR wait time was concentrated.

**Session timing**: `session_started_at` comes from `test_sessions.created_at`. `session_ended_at` is `MAX(results.created_at)` for that session. Both are approximate but accurate within a few seconds.

**Ambiguous column note**: The performance query joins `requests` with `results` (both have `test_session_id`). All WHERE clauses must qualify the table: `Sequel[:requests][:test_session_id]`.

### `config/banner.html.erb` — Performance Strip

When a user is on a session page (`/test_sessions/:id` or `/:suite/:version/:id`), a slim strip is injected below the header showing live metrics without navigating away. The strip:

1. Detects the session ID from `location.pathname` via regex
2. Fetches `/api/performance/test_sessions/:id`
3. Renders: `⚡ Performance · ⏱ [duration] · FHIR [time] (pct%) · Validator [time] (pct%) · [mini bar] · Full report →`
4. Hides itself if the API returns no data or errors

The Performance link in the header also updates its `href` to include `?session=` when a session ID is detected.

## Rack Routing Note

`Rack::URLMap` strips the mount prefix from `PATH_INFO`. When mounted at `/performance`, the app sees `PATH_INFO = ''` (empty string, not `/`). Routes must be `get '/'` for the dashboard root and `get '/test_sessions/:id'` for the API — not `get '/performance'`.

## Deployment

Both `config.ru` (web process) and `worker.rb` (Sidekiq) require `validator_timing.rb`. The migration runs automatically via Inferno's migration runner on startup.

The `/performance` and `/api/performance` routes are also added to `nginx.conf` as proxy pass targets so they reach Puma through the nginx-app sidecar:

```nginx
location /performance {
    proxy_pass http://puma_upstream;
}
location /api/performance/ {
    proxy_pass http://puma_upstream;
}
```

## Related

- [noecosystem-performance-analysis.md](./noecosystem-performance-analysis.md) — timing comparison between prod (noEcosystem false) and dev (noEcosystem true)
- [sparked-argo/docs/inferno-performance.md](https://github.com/hl7au/sparked-argo/blob/main/docs/inferno-performance.md) — infrastructure-level performance investigation (CPU, memory, I/O patterns)
