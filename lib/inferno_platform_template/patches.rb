# Upstream bug: InfernoSuiteGenerator::MSChecker sets @metadata in initialize
# but FHIRResourceNavigation#find_slice_via_discriminator calls metadata as a
# method, but the attr_reader is missing. Triggered by au_core_test_kit >= 1.4.1.
# Remove once inferno_suite_generator is updated.
require 'inferno_suite_generator/test_utils/ms_checker'

unless InfernoSuiteGenerator::MSChecker.method_defined?(:metadata)
  InfernoSuiteGenerator::MSChecker.attr_reader :metadata
end

# Fix cross-version validator-session collision (AU Core v1.0.0 <-> v2.0.0).
#
# inferno_core's `fhir_resource_validator` captures the declaring runnable's `id`
# EAGERLY as the validator's `test_suite_id`
# (dsl/fhir_resource_validation.rb: `Validator.new(name, id, ...)`). The au_core_test_kit
# generated suites declare `fhir_resource_validator` BEFORE their `id :au_core_vXXX`
# statement, so at capture time the suite's own id is unset. It then falls back to the
# runnable's `@base_id`, which inferno_core copies from the base class onto every subclass
# (dsl/runnable.rb VARIABLES_NOT_TO_COPY omits `:@base_id`), so the value is the literal
# base-class name "Inferno::Entities::TestSuite".
#
# Result: the au_core_v100 and au_core_v200 :default validators BOTH carry
# test_suite_id "Inferno::Entities::TestSuite". Validator sessions are keyed by
# (test_suite_id, validator_name, suite_options), so both IG versions collapse onto ONE
# validator-wrapper session/engine; whichever version built it wins, and the other 500s
# with `Unable to resolve profile http://hl7.org.au/fhir/core/StructureDefinition/
# au-core-*|<version>` (intermittent, race-dependent on run order).
#
# Fix: after finalize! (when suites are registered and their real ids are set), reset any
# validator still keyed by the base-class name to its owning suite's real id, so each
# suite gets its own session key/engine. Idempotent; only touches demonstrably-mis-keyed
# validators. Remove once au_core_test_kit declares `id` before the validator (or
# inferno_core adds :@base_id to VARIABLES_NOT_TO_COPY / resolves test_suite_id lazily).
module FixValidatorSessionKeyCollision
  BASE_SUITE_NAME = 'Inferno::Entities::TestSuite'

  def finalize!(...)
    result = super
    Inferno::Repositories::TestSuites.new.all.each do |suite|
      suite.fhir_validators.each_value do |validators|
        Array(validators).each do |validator|
          next unless validator.respond_to?(:test_suite_id)
          next unless validator.test_suite_id == BASE_SUITE_NAME

          validator.instance_variable_set(:@test_suite_id, suite.id)
        end
      end
    end
    result
  rescue StandardError => e
    Inferno::Application[:logger]&.warn("FixValidatorSessionKeyCollision skipped: #{e.class}: #{e.message}")
    result
  end
end

Inferno::Application.singleton_class.prepend(FixValidatorSessionKeyCollision)

# Collapse the N+1 subtree walk in Runnable#available_inputs.
#
# `available_inputs` merges this runnable's own inputs with those of its children. It
# obtains the child inputs from `children_available_inputs`, which recursively calls
# `available_inputs` on every descendant, so one call walks the entire subtree.
#
# Upstream calls that walk once per input inside the merge loop, plus once more to build
# the result (dsl/input_output_handling.rb):
#
#     available_inputs.each do |input, current_definition|
#       child_definition = children_available_inputs(selected_suite_options)[input]
#       current_definition.merge_with_child(child_definition)
#     end
#     available_inputs = children_available_inputs(selected_suite_options).merge(available_inputs)
#
# Nothing memoises it, so a runnable with N inputs performs N+1 full subtree walks, and
# because the recursion repeats that at every level the cost compounds with tree depth.
# The result is wildly super-linear: measured in the prod pod, au_ps_v100 (87 tests)
# serialises in 0.012s while au_core_v210_draft (498 tests) takes 4.86s. 5.7x the tests,
# 400x the time.
#
# This is on the hot path for POST /test_sessions, which renders the full suite tree
# (groups, tests and inputs) in the response. Session creation for the AU Core suites
# therefore costs 3.9-4.9s of pure CPU, which is what pushes concurrent session creation
# past the 15s Envoy route timeout and returns 504 at the app tier.
#
# The values are identical either way: `merge_with_child` mutates only the receiver and
# reads the child, so the two walks cannot observe each other and hoisting the call into a
# local is a pure win. Verified byte-identical serializer output across all four AU suites,
# 22-25x faster (au_core_v210_draft 4.93s -> 0.225s).
#
# Belongs upstream in inferno-core; `dsl/runnable.rb` already lists
# `@children_available_inputs` in VARIABLES_NOT_TO_COPY as "Needs to be recalculated",
# so the memoisation this restores appears to have been intended and lost. Remove this
# patch once inferno-core hoists or memoises the call itself.
# See https://github.com/inferno-framework/inferno-core
require 'inferno/dsl/input_output_handling'

module HoistChildrenAvailableInputs
  def available_inputs(selected_suite_options = nil)
    own_inputs =
      config.inputs
        .slice(*inputs)
        .each_with_object({}) do |(_, input), definitions|
          definitions[input.name.to_sym] = Inferno::Entities::Input.new(**input.to_hash)
        end

    # The single subtree walk, reused for both the per-input merge and the final merge.
    child_inputs = children_available_inputs(selected_suite_options)

    own_inputs.each do |input, current_definition|
      current_definition.merge_with_child(child_inputs[input])
    end

    order_available_inputs(child_inputs.merge(own_inputs))
  end
end

Inferno::DSL::InputOutputHandling.prepend(HoistChildrenAvailableInputs)

# Emit one OpenTelemetry trace per test instead of one unbounded trace per run.
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
if ENV['OTEL_EXPORTER_OTLP_ENDPOINT']
  require 'inferno/test_runner'

  module PerTestTraceRoot
    def run_test(test, scratch)
      tracer = OpenTelemetry.tracer_provider.tracer('inferno-worker')
      # Detach from the enclosing Sidekiq job span so the test span starts a new trace.
      OpenTelemetry::Context.with_current(OpenTelemetry::Context.empty) do
        tracer.in_span(
          "inferno.test #{test.id}",
          attributes: { 'inferno.test_run_id' => test_run.id, 'inferno.test_id' => test.id }
        ) do
          super
        end
      end
    end
  end

  Inferno::TestRunner.prepend(PerTestTraceRoot)
end
