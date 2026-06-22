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

# Released AU Core test kit (published on RubyGems by hl7au).
# NOTE: the newest published version is 1.4.0; code on the kit's master is ahead
# (1.4.2, unreleased). Once 1.4.2 is tagged + released, bump this to '~> 1.4'.
gem 'au_core_test_kit', '~> 1.4.0'

# AU PS test kit — no RubyGems release exists yet, so pin a stable commit.
gem 'au_ps_inferno', git: 'https://github.com/hl7au/au-ps-inferno', ref: '7dce73a0cd35fcc4ba84b15526f1b3345a9c9aaf'
