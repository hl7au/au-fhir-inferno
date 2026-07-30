# Record how long each test and group took to execute, on `results.duration_ms`.
#
# inferno-core stores `created_at` / `updated_at` on a result but never how long the
# runnable took, so nothing in the stack can answer the question a user actually asks
# about a slow run: "which test ate the time?". Per-test wall time can only be
# approximated today, by differencing consecutive results' `created_at` within a test
# run, which breaks down for waiting tests and for any result written out of execution
# order (parent roll-ups).
#
# This is a prototype of a change that belongs in inferno-core: `TestRunner` already
# brackets each runnable's execution and funnels every write through `#persist_result`,
# so core is the only place that can measure this correctly and the only place whose
# results UI can display it. Implemented here as a prepend so it can be validated
# against real AU Core runs on dev before being raised upstream. Remove this file, its
# migration and its env flag once inferno-core records duration itself.
# See https://github.com/inferno-framework/inferno-core
#
# Note this deliberately measures the whole of `run_test` / `run_group` (input loading,
# instance construction, the test block, saving outputs and writing the result), not just
# the test block: that total is the wall time the user experienced, and the difference is
# where inferno's own overhead would show up.
#
# Writing the result is a large part of that overhead, which is why it takes two writes to
# record (see `#persist_result`). Measured over a 498-test AU Core run on dev:
#
#   executing tests                      226.0 s   54%
#   writing their results                186.6 s   45%
#   everything else in the run             2.2 s    1%
#
# `Repositories::Results#create` writes a row per message and per request, and
# `Repositories::Requests#create` a row per HTTP header, all one INSERT at a time: 38,139
# rows for that run, 29,889 of them headers. Measuring only up to the start of that write
# would have reported 226.0 s of a 414.8 s run and, worse, would have understated exactly
# the request-heavy tests a user is looking for (a 3.3 s test reporting 1.1 s).

require 'inferno'
require 'inferno/test_runner'
require 'inferno/apps/web/serializers/result'

module InfernoPlatformTemplate
  # Times each runnable and attaches the result to the row `TestRunner` persists for it.
  #
  # `TestRunner` is instantiated once per test run and executes it on a single thread,
  # so a plain instance variable is sufficient state; no thread-locals needed.
  module ResultDurationPatch
    # One frame per runnable currently executing, innermost last. A `nil` frame marks a
    # region whose writes must NOT be attributed a duration.
    def duration_frames
      @duration_frames ||= []
    end

    # `...` forwarding throughout so the patch does not restate, and cannot drift from,
    # inferno-core's signatures.
    def run_test(...)
      duration_frames.push(monotonic_ms)
      super
    ensure
      duration_frames.pop
    end

    def run_group(...)
      duration_frames.push(monotonic_ms)
      super
    ensure
      duration_frames.pop
    end

    # Parent roll-ups recompute an ancestor's result after its children finish, long
    # after the ancestor itself ran. Elapsed time is meaningless for those writes, and
    # the enclosing test's frame is still on the stack when they happen, so push a nil
    # frame to suppress attribution for the whole recursive roll-up.
    def update_parent_result(...)
      duration_frames.push(nil)
      super
    ensure
      duration_frames.pop
    end

    # A result row cannot carry the cost of writing itself, so this takes two writes: the
    # INSERT gets the time spent executing the runnable, then an UPDATE corrects it to the
    # elapsed time including persistence, once persistence has finished.
    #
    # `super` here is exactly the whole write (`results_repo.create`, which cascades into
    # the message, request and header rows), so the second reading covers all of it and
    # none of the parent roll-up that `run_group` performs afterwards.
    #
    # The extra UPDATE is one row against a primary key, per result: 533 of them for the
    # run above, against the 38,139 INSERTs it already performs.
    def persist_result(params)
      started_at_ms = duration_frames.last
      return super if started_at_ms.nil?

      result = super(params.merge(duration_ms: monotonic_ms - started_at_ms))
      record_total_duration(result, monotonic_ms - started_at_ms)
    end

    private

    # Keeps the in-memory entity consistent with the row. `TestRunner` hands the entity
    # back to the caller in `run_results`, so leaving it holding the execution-only value
    # would make the API and a directly returned result disagree.
    def record_total_duration(result, duration_ms)
      results_repo.update(result.id, duration_ms:)
      result.duration_ms = duration_ms
      result
    end

    def monotonic_ms
      Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
    end
  end

  # `Inferno::Entities::Entity#initialize` assigns only the attributes named in the
  # class's ATTRIBUTES list, so a `duration_ms` coming back from the database is
  # otherwise dropped on the way from the repository to the entity.
  module ResultDurationAttribute
    attr_accessor :duration_ms

    def initialize(params)
      super
      @duration_ms = params[:duration_ms]
    end
  end
end

Inferno::TestRunner.prepend(InfernoPlatformTemplate::ResultDurationPatch)
Inferno::Entities::Result.prepend(InfernoPlatformTemplate::ResultDurationAttribute)

# The result serializer is an explicit Blueprinter whitelist, so the field has to be
# declared for it to reach /api/test_sessions/:id/results. `field_present?` treats 0 as
# present (only nil/false/empty are blank), so sub-millisecond runnables still report.
Inferno::Web::Serializers::Result.class_eval do
  field :duration_ms, if: :field_present?
end
