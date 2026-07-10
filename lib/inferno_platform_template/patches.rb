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
