# Answers GET /site-config.json with the per-environment facts the static kit pages need
# at runtime.
#
# WHY THIS EXISTS
#
# Staging and production run one image with one generated Jekyll site (build once,
# deploy many), so the site cannot carry anything that differs between them. The kit
# pages need exactly one such fact: where the ci-build environment lives. Staging offers
# each kit's CI-build suite as a radio that launches on that host; production must not.
# That host is the chart's inferno.ciBuildHost, written to INFERNO_CI_BUILD_HOST, and this
# endpoint is how a page reads it.
#
# The response also lists the CI-build suites THIS environment registers, with their
# titles, so a page on staging can ask the ci-build host what it actually runs before
# offering a radio for it. That makes the radio fail closed (no radio while the ci-build
# environment is down or not yet deployed) and shows the IG version from the suite title
# the kit generated, which a static page would get wrong after the next CI-build version.
# Hence the wildcard CORS header: everything here is public, and the only caller that
# needs it cross-origin is a kit page on another of our hosts.
#
#   {"ciBuildHost": "https://ci-build.inferno.sparked-fhir.com" | null,
#    "ciBuildSuites": [{"id": "au_ps_ci_build", "title": "AU PS 1.1.0-ci-build ..."}]}
#
# A host that is not a bare https origin (or http://localhost) is reported as null rather than passed to the
# page, so a typo in a values file cannot point a form POST somewhere unexpected.
require 'json'

module InfernoPlatformTemplate
  class SiteConfig
    PATH = '/site-config.json'.freeze
    SERVABLE_METHODS = ['GET', 'HEAD'].freeze

    # Every kit names its CI-build suite <prefix>_ci_build (docs/kit-ci-build-contract.md).
    CI_BUILD_SUITE_SUFFIX = '_ci_build'.freeze

    # A bare https origin, or plain-http localhost so two local instances can stand in for
    # staging and the ci-build environment.
    HOST_PATTERN = %r{\A(https://[a-z0-9.-]+|http://localhost)(:\d+)?\z}

    HEADERS = {
      'Content-Type' => 'application/json',
      'Access-Control-Allow-Origin' => '*',
      # Short, because the suite titles change when the ci-build image rolls.
      'Cache-Control' => 'public, max-age=300'
    }.freeze

    # ci_build_host and suites are overridable for specs; by default they are read from the
    # environment and from Inferno's suite registry on each request, which is cheap (a
    # handful of in-memory suites) and never stale.
    def initialize(app, ci_build_host: nil, suites: nil)
      @app = app
      @ci_build_host = ci_build_host
      @suites = suites
    end

    def call(env)
      return @app.call(env) unless env['PATH_INFO'] == PATH
      return @app.call(env) unless SERVABLE_METHODS.include?(env['REQUEST_METHOD'])

      body = env['REQUEST_METHOD'] == 'HEAD' ? [] : [JSON.generate(config)]
      [200, HEADERS.dup, body]
    end

    private

    def config
      { ciBuildHost: ci_build_host, ciBuildSuites: ci_build_suites }
    end

    def ci_build_host
      host = (@ci_build_host || ENV.fetch('INFERNO_CI_BUILD_HOST', '')).to_s.strip
      HOST_PATTERN.match?(host) ? host : nil
    end

    def ci_build_suites
      suites
        .select { |suite| suite.id.to_s.end_with?(CI_BUILD_SUITE_SUFFIX) }
        .map { |suite| { id: suite.id.to_s, title: suite.title.to_s } }
    end

    def suites
      return @suites unless @suites.nil?

      Inferno::Repositories::TestSuites.all
    end
  end
end
