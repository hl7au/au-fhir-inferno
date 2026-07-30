# Per-runnable duration (`results.duration_ms`)

Records how long each test and group took to execute. Dev-only, gated by
`RESULT_DURATION_ENABLED` / `inferno.resultDuration`.

This is a **prototype of an inferno-core change**, staged here so it can be validated
against real AU Core runs before being raised upstream. It is not intended to live in this
repository long-term.

## Why

inferno-core stores `created_at` / `updated_at` on a result but never how long the runnable
took. Nothing in the stack can therefore answer the question users actually ask about a slow
run: *which test ate the time?*

The nearest approximation available today is differencing consecutive results'
`created_at` within a test run. That breaks down for waiting tests and for any result
written out of execution order, which parent roll-ups are.

This is also a different question from the one the retired `/performance` page answered.
That page summed outbound FHIR wait and validator wait per session: neither is per-test wall
time, and neither accounted for Inferno's own CPU. Deep per-call timing now comes from the
OpenTelemetry spans both processes emit to Tempo, which cover the same calls with full test
attribution; this column is the summary figure that belongs next to the result itself.

## How it works

`lib/inferno_platform_template/result_duration.rb` prepends `Inferno::TestRunner`, which is
the only place that can measure this correctly: it brackets each runnable's execution and
funnels every write through `#persist_result`.

The patch keeps a stack of monotonic start times, one frame per runnable currently
executing. `TestRunner` is instantiated per test run and executes it on one thread, so a
plain instance variable suffices.

| Call | Frame pushed | Effect |
|---|---|---|
| `run_test` | start time | the test's own row gets its elapsed time |
| `run_group` | start time | the group's row spans all of its children |
| `update_parent_result` | `nil` | suppresses attribution for the recursive roll-up |

The `nil` frame matters. Roll-ups recompute an ancestor's result after its children
finish, long after the ancestor ran, and they happen while the enclosing test's frame is
still on the stack. Without suppression a parent would inherit its child's elapsed time.

The duration measures the whole of `run_test` / `run_group`, including input loading,
instance construction, saving outputs and writing the result, not just the test block. That
total is the wall time the user experienced, and the difference is where Inferno's own
overhead shows up.

### Why it takes two writes

A result row cannot carry the cost of writing itself. `#persist_result` therefore inserts
the time spent executing the runnable, then updates the row with the elapsed time once the
write has finished. `super` inside `#persist_result` is exactly `Repositories::Results#create`,
so the second reading covers the whole write and none of the parent roll-up that `run_group`
performs afterwards.

The extra write earns its place, because on this workload persistence is not a rounding
error. Measured over a 498-test AU Core run on dev (session `bcT7dNjmwrt`, run duration
414.8 s), against the OpenTelemetry `inferno.test` spans that bracket the same method:

| | | |
|---|---|---|
| Executing tests | 226.0 s | 54% |
| Writing their results | 186.6 s | 45% |
| Everything else in the run | 2.2 s | 1% |

`Repositories::Results#create` writes a row per message and per request, and
`Repositories::Requests#create` a row per HTTP header, all one INSERT at a time: **38,139
rows** for that run, 29,889 of them headers. The cost tracks request count almost exactly
(r = 0.906, roughly 100 ms per persisted request), so measuring only up to the start of the
write would have understated precisely the request-heavy tests a user is hunting for. One
test recorded 1.07 s against 3.31 s actually elapsed.

The corrective UPDATE is a single row by primary key, one per result: 533 for that run,
against the 38,139 INSERTs it already performs.

Three further patches are needed because inferno-core whitelists at every layer:

| Layer | Why |
|---|---|
| `db/migrate/003_add_duration_ms_to_results.rb` | the column itself. `Repository#create` slices params to `Model.columns`, so no repository change is needed once it exists |
| `Inferno::Entities::Result` | `Entity#initialize` assigns only attributes named in the class's `ATTRIBUTES`, so a `duration_ms` from the database is otherwise dropped |
| `Inferno::Web::Serializers::Result` | an explicit Blueprinter whitelist; unlisted fields never reach the API |

Both processes load the file: the worker does the measuring (test runs execute there), the
web process needs the entity and serializer patches to expose the value.

## Validating on dev

```
GET /api/test_sessions/:id/results
```

Each result carries `duration_ms`. Worth checking on a full AU Core run:

- tests have plausible durations, groups are >= the sum of their children
- suite and group roll-up rows are not carrying a child's duration
- summed test durations versus the session's wall time: the gap is Inferno overhead plus
  time outside test execution, and quantifying it is the point of the exercise
- waiting tests, which record time up to the wait; on resume `TestRunner` returns the
  existing result without persisting again, so the post-resume portion is not counted

The check worth repeating is against the traces, since they measure the same method from
outside the process and so cannot share a mistake with the patch:

```
{ span.inferno.test_session_id = "<session>" && name = "inferno.test" }
```

Sum those span durations and compare to the summed `duration_ms` for the session's tests.
They should now agree within the tracing overhead itself (a few ms per test). A large,
request-correlated shortfall in `duration_ms` means the corrective update is not running.

## Known limits

- **No UI.** inferno-core ships a prebuilt React bundle (`config.ru` serves
  `Inferno::Utils::StaticAssets`), so durations cannot appear in the results tree without a
  core fork and a frontend build. Data and API only.
- `Result#to_hash` is left alone, so `duration_ms` is absent there. Nothing in this
  repository reads it; the serializer is what feeds the API.
- `db/migrate` still contains `001` and `002`, which built the retired performance
  monitoring schema, and `004`, which drops it again. Sequel's IntegerMigrator refuses to
  run against a database recorded at a higher version than the files present, so deleting
  applied migrations would break the dev database. Enabling the flag on a fresh database
  therefore creates and immediately drops those objects. See the note in the `Rakefile`.

## Upstreaming

Split the change in two. The data and API half is what this prototype validates and is the
part every test kit benefits from; raise it first. The UI half needs the frontend build and
can follow.

Once inferno-core records duration itself, delete `result_duration.rb`, migration `003`,
the `RESULT_DURATION_ENABLED` plumbing and this document.

## Related

- [tracing.md](./tracing.md) - the OpenTelemetry spans covering the same test executions.
  `duration_ms` is the summary number to quote to a user; the traces are how you work out why
  it is what it is.
