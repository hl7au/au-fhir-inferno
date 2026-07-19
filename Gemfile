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

# Released AU Core test kit (published on RubyGems by hl7au). '~> 1.4.3' means
# >= 1.4.3, < 1.5.0; Gemfile.lock pins the exact version. 1.4.3 is the first release that
# includes the AU Core 2.1.0-draft suite. Bump the lock (bundle update au_core_test_kit)
# to adopt new 1.4.x releases.
gem 'au_core_test_kit', '~> 1.4.3'

# AU PS test kit — no RubyGems release exists yet, so pin a stable commit. Targets the
# AU PS 1.0.0 IG (suite id au_ps_v100); pinned to a stable au-ps-inferno commit.
gem 'au_ps_inferno', git: 'https://github.com/hl7au/au-ps-inferno', ref: 'b2d03bb1f87cb2f01a2719a2d2deb42096a9b416'
