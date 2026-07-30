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
instance construction and output persistence, not just the test block. That total is the
wall time the user experienced, and the difference is where Inferno's own overhead shows up.

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
