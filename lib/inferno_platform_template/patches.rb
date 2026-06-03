# Upstream bug: InfernoSuiteGenerator::MSChecker sets @metadata in initialize
# but FHIRResourceNavigation#find_slice_via_discriminator calls metadata as a
# method — missing attr_reader. Triggered by au_core_test_kit >= 1.4.1.
# Remove once inferno_suite_generator is updated.
require 'inferno_suite_generator/test_utils/ms_checker'

unless InfernoSuiteGenerator::MSChecker.method_defined?(:metadata)
  InfernoSuiteGenerator::MSChecker.attr_reader :metadata
end
