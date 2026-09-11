# Sends suite landing pages to their test kit page on the static site.
#
# WHY THIS EXISTS
#
# Inferno Core is suite-oriented: /suites/<suite_id> is a real page it will happily
# render. This platform is test-kit-oriented, and the page a user should see for a kit is
# the Jekyll page (/test-kits/au-core/), which carries the description, the suite picker
# and the recent-session list. The case that matters is navigating backwards out of a
# session: the browser walks up to /suites/<suite_id> and, without this, the user lands
# on a bare suite page instead of the kit page they started from.
#
# These rules used to be `rewrite ... redirect` directives in nginx.conf, alongside the
# static site itself. Both moved into the application image together; see static_site.rb
# for the reasoning and the sequencing that keeps nginx alive for prod until it is
# promoted.
#
# PREFIX MATCHING RATHER THAN A VERSION REGEX
#
# nginx matched `^/suites/au_core_v\d+(_ballot)?/?$`, which does not match
# au_core_v300_ballot1: the trailing digit after _ballot falls outside the group, so the
# suite that is actually current on this platform was never redirected. Matching on the
# kit's id prefix has no such failure mode, and a new suite version needs no change here.
#
# THE BOUNDARY THAT MUST HOLD
#
# Only ONE path segment under /suites may match. Everything else under /suites belongs to
# Inferno Core, and taking any of it over breaks the application: session pages
# (/suites/au_core_v300_ballot1/<uuid>), the API (/suites/api/...), session creation
# (/suites/test_sessions/...), custom pages and the bundled assets
# (/suites/public/...). Hence the explicit single-segment test below.
module InfernoPlatformTemplate
  class SuiteRedirects
    SUITE_PREFIX = '/suites'.freeze
    TEST_KITS_PATH = '/test-kits/'.freeze

    # Suite id prefix => test kit page. Only kits this platform actually hosts belong
    # here; the site is the source of truth and a spec asserts every suite id listed
    # under `suites:` in web/_test_kits/*.md is covered, so the two cannot drift.
    # nginx also carried ipa_v* and us_core_v* rules, left over from the upstream
    # template. Neither kit is hosted here and neither has a page to redirect to, so
    # they are deliberately not carried over.
    KIT_PAGES = {
      'au_core_' => '/test-kits/au-core/',
      'au_ps_' => '/test-kits/au-ps/'
    }.freeze

    SERVABLE_METHODS = ['GET', 'HEAD'].freeze
    REDIRECT_STATUS = 302

    def initialize(app)
      @app = app
    end

    def call(env)
      return @app.call(env) unless SERVABLE_METHODS.include?(env['REQUEST_METHOD'])

      target = redirect_target(env['PATH_INFO'].to_s)
      return @app.call(env) if target.nil?

      redirect(target)
    end

    private

    def redirect_target(path)
      # A trailing slash was optional in the nginx rules, so /suites/ and
      # /suites/au_ps_v100/ behave like their unslashed forms.
      path = path.chomp('/')
      return TEST_KITS_PATH if path == SUITE_PREFIX
      return nil unless path.start_with?("#{SUITE_PREFIX}/")

      suite_id = path.delete_prefix("#{SUITE_PREFIX}/")
      # Anything deeper than one segment is Inferno Core's, not a suite landing page.
      return nil if suite_id.include?('/')

      _prefix, page = KIT_PAGES.find { |prefix, _page| suite_id.start_with?(prefix) }
      page
    end

    # 302, as the nginx `redirect` flag emitted. The mapping is a product decision rather
    # than a permanent fact about the URL space, so it should not be cached forever by
    # browsers that have followed it once.
    def redirect(location)
      [REDIRECT_STATUS, { 'Location' => location, 'Content-Type' => 'text/plain' }, ["Found: #{location}"]]
    end
  end
end
