# frozen_string_literal: true

# PRODUCTION / released dependency set. This is the DEFAULT Gemfile (the one bundler
# uses unless BUNDLE_GEMFILE says otherwise) and the set that ships to prod
# (inferno.hl7.org.au). It pins the test kits to RELEASED gem versions, or to a stable
# commit where no release exists yet.
#
# For the dev environment and local work against bleeding-edge, unreleased test-kit
# commits, use Gemfile.dev (which has its own Gemfile.dev.lock):
#
#   BUNDLE_GEMFILE=Gemfile.dev bundle install
#
# Keeping the unreleased test-kit SHAs in Gemfile.dev means this file and Gemfile.lock
# stay identical on the development and master branches, so development -> master
# merges never conflict on, or silently leak unreleased versions into, prod.

eval_gemfile 'Gemfile.common'

# Released AU Core test kit (published on RubyGems by hl7au). '~> 1.4.6' means
# >= 1.4.6, < 1.5.0; Gemfile.lock pins the exact version. 1.4.6 is the first release whose
# ReferenceResolutionTest validates through the supported DSL rather than the Validator
# internals inferno_core removed in v1.1.0, so it is the floor for the 1.4.x line.
gem 'au_core_test_kit', '~> 1.4.6'

# Released AU PS test kit (published on RubyGems by hl7au). '~> 1.0.1' means
# >= 1.0.1, < 1.1.0; Gemfile.lock pins the exact version. 1.0.1 is the first release
# without the 'inferno_core ~> 1.0.6' cap, so it is the floor for the 1.4.x line.
gem 'au_ps_inferno', '~> 1.0.1'
