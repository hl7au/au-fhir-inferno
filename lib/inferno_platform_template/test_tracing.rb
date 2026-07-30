# Emit one OpenTelemetry trace per test instead of one unbounded trace per run.
#
# Lives outside patches.rb because it is not a workaround for an upstream bug: it is
# instrumentation, it only does anything in the process that executes test runs (the Sidekiq
# worker, see worker.rb), and it is gated on tracing being configured at all. Keeping it
# separate also keeps it loadable on its own, which patches.rb is not once
# Inferno::Application has been finalized and frozen.
#
# inferno-core executes an entire test run inside a SINGLE Sidekiq job
# (Inferno::Jobs::ExecuteTestRun -> TestRunner#start -> recursive #run). With the Sidekiq
# OTel instrumentation enabled (worker.rb), that job's server span becomes the trace root,
# so the whole run collapses into a single trace: every validator and terminology HTTP
# request, context propagated by the Faraday / Net::HTTP instrumentation. A full run can
# be many minutes and tens of thousands of spans, which is effectively unusable telemetry:
# trace backends reject or truncate traces above a per-trace size limit (e.g. Tempo's
# max_bytes_per_trace, 5MB by default), silently losing spans, and no trace UI can render
# a multi-minute, ten-thousand-span trace anyway.
#
# Wrap each test in a fresh root span (empty parent context => new trace id) so every test
# is its own bounded, queryable trace, with its downstream calls as children and a shared
# inferno.test_run_id attribute to correlate the tests of one run. This belongs upstream in
# inferno-core (which owns TestRunner and the one-job-per-run model); remove this patch once
# it offers native per-test tracing. See https://github.com/inferno-framework/inferno-core
#
# The span is named with the constant 'inferno.test' and everything identifying goes in
# attributes. Putting the test id in the span NAME was actively harmful: Tempo's
# metrics-generator uses span_name as a span-metrics dimension, so every test of every suite
# version became its own series. On the sparked cluster that was 1417 of 3455 span_name
# values, and those series are useless by construction: a test emits exactly one span per
# run, so a per-test series holds a single observation and increase() over it returns 0.
# Collapsing the name deletes that cardinality and, as a side effect, turns
# span_name="inferno.test" into one meaningful series, total test-execution time, queryable
# over Mimir's retention rather than Tempo's.
#
# Nothing is lost for querying or reading. TraceQL filters and groups on attributes
# (span.inferno.test_id), select() lifts them into table columns, and TraceQL metrics
# aggregate by them:
#   { span.inferno.test_run_id = "..." } | quantile_over_time(duration, .95) by (span.inferno.group_id)
if ENV['OTEL_EXPORTER_OTLP_ENDPOINT']
  require 'inferno/test_runner'

  module PerTestTraceRoot
    SPAN_NAME = 'inferno.test'.freeze
    PERSIST_SPAN_NAME = 'inferno.persist_result'.freeze

    def run_test(test, scratch)
      # Detach from the enclosing Sidekiq job span so the test span starts a new trace.
      OpenTelemetry::Context.with_current(OpenTelemetry::Context.empty) do
        tracer.in_span(SPAN_NAME, attributes: test_span_attributes(test)) do |span|
          super.tap { |result| annotate_test_result(span, result) }
        end
      end
    end

    # Writing a result is the second largest cost in a run, behind executing the tests
    # themselves and ahead of everything else: 186.6 s of a 414.8 s AU Core run on dev.
    # `Repositories::Results#create` writes a row per message and per request, and
    # `Repositories::Requests#create` a row per HTTP header, one INSERT at a time, which
    # came to 38,139 rows for that run.
    #
    # It is worth its own span because nothing else can see it. It is not an HTTP call, so
    # no instrumentation covers it, and it is inside `run_test`, so it is already counted
    # in the test span and in `results.duration_ms` without being distinguishable there.
    #
    # It carries its own identity rather than relying on the parent test span for it.
    # Being a child is not enough: TraceQL's `span.` filters match attributes on the span
    # itself, so a session-scoped panel written the way every other one is written returns
    # nothing, and only a trace-level conjunction reaches it:
    #
    #   { span.inferno.test_session_id = "..." } && { name = "inferno.persist_result" }
    #
    # That form works for search and select(), but it returns the matched spans from both
    # filters, so a table gets a spurious near-empty row per trace, and an aggregate
    # grouped by a dimension only the test span carries splits in two. Measured on dev
    # before this change, `sum_over_time(duration) by (span.inferno.suite_id)` over that
    # conjunction returned two series, `au_core_v210_draft` and `nil`, with every one of
    # the persist spans in `nil`.
    def persist_result(params)
      tracer.in_span(PERSIST_SPAN_NAME, attributes: persist_span_attributes(params)) { super }
    end

    # A whole run executes inside one Sidekiq job, and the Sidekiq instrumentation already
    # spans that job, so its duration is the run's duration. It carries no Inferno identity
    # though, which makes the job span for a known run impossible to find. Annotating the
    # enclosing span is cheaper than emitting a second, redundant run-level span. When
    # tracing is off the current span is a no-op span and add_attributes does nothing.
    def start
      OpenTelemetry::Trace.current_span.add_attributes(run_span_attributes)
      super
    end

    private

    def tracer
      OpenTelemetry.tracer_provider.tracer('inferno-worker')
    end

    # The row counts are what make a slow write explicable rather than merely visible: the
    # cost tracks the number of requests being written almost exactly.
    #
    # The runnable id comes from the params, because `persist_result` receives the
    # runnable's `reference_hash` merged in and is called for groups and suite roll-ups as
    # well as tests. Exactly one of `test_id` / `test_group_id` is present on any given
    # write, neither on a suite, and `compact` drops the absent ones rather than exporting
    # nils. Attribute names match the test span's, so the two aggregate together.
    def persist_span_attributes(params)
      {
        'inferno.test_session_id' => test_session.id,
        'inferno.test_run_id' => test_run.id,
        'inferno.suite_id' => test_session.test_suite_id,
        'inferno.test_id' => params[:test_id],
        'inferno.group_id' => params[:test_group_id],
        'inferno.messages_persisted' => (params[:messages] || []).size,
        'inferno.requests_persisted' => (params[:requests] || []).size
      }.compact
    end

    def run_span_attributes
      {
        'inferno.test_run_id' => test_run.id,
        'inferno.test_session_id' => test_session.id,
        'inferno.suite_id' => test_session.test_suite_id
      }.compact
    end

    def test_span_attributes(test)
      {
        'inferno.test_run_id' => test_run.id,
        'inferno.test_session_id' => test_session.id,
        'inferno.test_id' => test.id,
        # short_id is the label the Inferno UI shows ("1.2.03"), so it is what a user reads
        # back to you when reporting a slow test.
        'inferno.test_short_id' => test.short_id,
        'inferno.test_title' => test.title,
        'inferno.suite_id' => runnable_suite_id(test),
        'inferno.group_id' => test.parent&.id
      }.compact
    end

    # Runnable#suite walks up the parent chain assuming it terminates in a TestSuite, so it
    # raises on a runnable not mounted under one. Identity is a nice-to-have on a span; never
    # let collecting it break a test run.
    def runnable_suite_id(test)
      test.suite&.id
    rescue StandardError
      nil
    end

    def annotate_test_result(span, result)
      outcome = result.result if result.respond_to?(:result)
      return if outcome.nil?

      span.set_attribute('inferno.result', outcome)
      # Only 'error' sets span status. A failing test is the expected outcome of testing a
      # non-conformant server, not a fault in the run; marking it as a span error would put
      # every conformance failure into error-rate panels and alerts.
      return unless outcome == 'error'

      span.status = OpenTelemetry::Trace::Status.error("test result: #{outcome}")
    end
  end

  Inferno::TestRunner.prepend(PerTestTraceRoot)
end
