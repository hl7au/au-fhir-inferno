require 'securerandom'
require 'inferno/dsl/fhir_validation'

# Records wall-clock round-trip time for every validator API call made during
# test execution. Stored in the `validator_timing` table (added by migration
# 002_add_validator_timing.rb) so the performance page can show FHIR server
# time vs validator API time side-by-side.
#
# Uses `...` forwarding so argument defaults in the original method (notably
# `resource: self.resource`) are evaluated correctly in the test instance context.
module InfernoPlatformTemplate
  module ValidatorTimingPatch
    def resource_is_valid?(...)
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
      result = super
      elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond) - t0).to_i

      begin
        db = Sequel::DATABASES.first
        if db&.table_exists?(:validator_timing)
          db[:validator_timing].insert(
            id: SecureRandom.uuid,
            test_session_id: test_session_id,
            validator_url: ENV.fetch('FHIR_RESOURCE_VALIDATOR_URL', 'http://validator-api:3500'),
            duration_ms: elapsed,
            created_at: Time.now.utc
          )
        end
      rescue StandardError
        # Never let timing recording failure affect test execution
      end

      result
    end
  end
end

Inferno::DSL::FhirValidation.prepend(InfernoPlatformTemplate::ValidatorTimingPatch)
