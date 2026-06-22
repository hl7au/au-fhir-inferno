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

# Released AU Core test kit (published on RubyGems by hl7au). '~> 1.4.0' means
# >= 1.4.0, < 1.5.0; Gemfile.lock pins the exact version (currently 1.4.2). Bump the
# lock (bundle update au_core_test_kit) to adopt new 1.4.x releases; widen to '~> 1.4'
# only if you want 1.5+ automatically.
gem 'au_core_test_kit', '~> 1.4.0'

# AU PS test kit — no RubyGems release exists yet, so pin a stable commit on master
# (currently master HEAD, which includes the noEcosystem validator perf fix).
gem 'au_ps_inferno', git: 'https://github.com/hl7au/au-ps-inferno', ref: '3cda64eeb2fd1c1677d937cd724aa52b98b62617'
