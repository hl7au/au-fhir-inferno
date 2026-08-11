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
# merges never conflict on — or silently leak unreleased versions into — prod.

eval_gemfile 'Gemfile.common'

# inferno_core stays on the 1.0.x line here while the 1.4.x upgrade is staged through the
# dev and preview environments (see Gemfile.dev). Prod cannot move yet: the RELEASED
# au_ps_inferno 1.0.0 declares 'inferno_core ~> 1.0.6', which resolves to '< 1.1.0', so
# the bundle below will not resolve against 1.4.x at all; and the RELEASED
# au_core_test_kit 1.4.5 still validates reference targets out of three Validator methods
# that inferno_core removed in v1.1.0, so the AU Core v1.0.0 reference-resolution tests
# would raise NoMethodError even if it did resolve. Both fixes are on branches awaiting
# release (au_ps_inferno 1.0.1, au_core_test_kit 1.4.6). Once those ship, bump the pins
# below, move this line to '~> 1.4.2', and fold it back into Gemfile.common.
gem 'inferno_core', '~> 1.0.6'

# Unchanged from what prod runs today. Deliberately NOT moved to the ref Gemfile.dev uses:
# that ref carries generator behaviour changes (foreign reference-target versioning, a
# configurable SNOMED CT edition, dropped PATCH versionId checking) which have nothing to
# do with this upgrade and are not covered by its before/after evidence, since both legs
# of that comparison ran the newer ref. Bump this in its own change, with its own run.
gem 'inferno_suite_generator', github: 'hl7au/inferno_suite_generator', ref: '9b0d17ef2ade2027cce33cca5539f84ab5bf5f85'

# Released AU Core test kit (published on RubyGems by hl7au). '~> 1.4.5' means
# >= 1.4.5, < 1.5.0; Gemfile.lock pins the exact version. 1.4.5 is the first release that
# includes the AU Core 3.0.0-ballot1 suite. Bump the lock (bundle update au_core_test_kit)
# to adopt new 1.4.x releases.
gem 'au_core_test_kit', '~> 1.4.5'

# Released AU PS test kit (published on RubyGems by hl7au). '~> 1.0.0' means
# >= 1.0.0, < 1.1.0; Gemfile.lock pins the exact version.
gem 'au_ps_inferno', '~> 1.0.0'
