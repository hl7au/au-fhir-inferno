# Keeps Inferno's absolute redirects on the hostname the client actually used.
#
# WHY THIS EXISTS
#
# inferno_core builds some redirects as ABSOLUTE URLs from a single value fixed at boot:
# Application['base_url'] is URI.join(INFERNO_HOST, BASE_PATH), and both the session form
# POST (POST /suites/<suite_id>) and the session show route
# (GET /suites/test_sessions/<id>) send the browser to "<base_url>/<suite>/<session id>".
# One baked host cannot be right for every hostname an environment answers on:
#
#   * prod serves inferno.sparked-fhir.com AND inferno.hl7.org.au, so whichever one
#     INFERNO_HOST does not name would bounce its users to the other mid-flow;
#   * under build-once, the dev-flavoured image (which every preview also runs) carries
#     the dev host, so a preview creating a session would send the user to DEV.
#
# nginx solved this with `proxy_redirect ~^https?://[^/]+(/suites/.*)$ $fwd_scheme://$host$1`
# on its /suites location: rewrite the Location header to the scheme and host the client
# used. This middleware is that rule, and it is why removing nginx does not regress
# multi-hostname environments. INFERNO_HOST still matters and is still set per
# environment (it is the canonical origin for the page's canonical link and og: metadata,
# and for any other absolute URL inferno builds); this only stops it from moving a user
# off the hostname they are already on.
#
# SCOPED DELIBERATELY, BECAUSE A LOCATION HEADER IS NOT ALWAYS OURS TO REWRITE
#
# nginx's rule matched ANY absolute redirect out of /suites. That is too broad in
# principle: a test kit can redirect a user to an authorization server, and rewriting the
# host of an OAuth redirect would break the flow and could send a code-bearing URL
# somewhere it does not belong. Three conditions must all hold before anything is
# touched:
#
#   1. the Location is absolute (a relative one already stays on the request's host);
#   2. its origin is OUR configured origin, INFERNO_HOST, not a third party;
#   3. its path is inside Inferno's base path (/suites), not merely on our host.
#
# The configured origin and base path are read from Application on EVERY request rather
# than captured at boot, so nothing here goes stale if either is re-registered. The two
# keyword overrides exist for specs: Inferno::Application is a frozen container once
# finalised, so its values cannot be stubbed, and a spec that depended on the ambient
# .env would assert whatever the machine happened to be configured for.
module InfernoPlatformTemplate
  class RequestHostRedirects
    LOCATION_HEADER = 'Location'.freeze

    def initialize(app, inferno_host: nil, base_path: nil)
      @app = app
      @inferno_host = inferno_host
      @base_path = base_path
    end

    def call(env)
      status, headers, body = @app.call(env)

      # Rack 2 conventionally capitalises, but nothing enforces it, so find the key that
      # is actually there and write back to that same key.
      key = headers.keys.find { |name| name.to_s.casecmp(LOCATION_HEADER).zero? }
      return [status, headers, body] if key.nil?

      rewritten = rewritten_location(headers[key], env)
      headers[key] = rewritten if rewritten

      [status, headers, body]
    end

    private

    # Returns the replacement Location, or nil to leave the response exactly as it is.
    # Every "leave it alone" path returns nil rather than raising: a Location this
    # middleware does not understand is the application's business, not a failure.
    def rewritten_location(location, env)
      configured = parse(configured_host)
      target = parse(location)
      return nil if configured.nil? || target.nil?

      # A relative Location has no host, and the browser resolves it against the request,
      # which is already the behaviour this middleware exists to produce.
      return nil if target.host.nil?
      return nil unless same_origin?(target, configured)
      return nil unless inferno_path?(target.path)

      host = request_host(env)
      return nil if host.nil? || host.empty?

      query = target.query.nil? ? '' : "?#{target.query}"

      "#{request_scheme(env)}://#{host}#{target.path}#{query}"
    end

    def configured_host
      @inferno_host || Inferno::Application['inferno_host']
    end

    def base_path
      @base_path || Inferno::Application['base_path']
    end

    def parse(value)
      URI.parse(value.to_s)
    rescue URI::InvalidURIError
      nil
    end

    # URI#port fills in the scheme's default, so https://host and https://host:443 compare
    # equal, which is what a browser would do too. Hosts and schemes are case-insensitive.
    def same_origin?(target, configured)
      target.scheme.to_s.casecmp(configured.scheme.to_s).zero? &&
        target.host.to_s.casecmp(configured.host.to_s).zero? &&
        target.port == configured.port
    end

    # BASE_PATH is registered without a leading slash ("suites"). Blank means inferno is
    # mounted at the root, in which case every path on our own origin is inferno's.
    def inferno_path?(path)
      prefix = base_path.to_s.delete_prefix('/').delete_suffix('/')
      return true if prefix.empty?

      prefix = "/#{prefix}"
      path == prefix || path.to_s.start_with?("#{prefix}/")
    end

    # TLS terminates at the gateway, so rack.url_scheme is always http on the wire and
    # X-Forwarded-Proto carries what the client used. Proxies may append rather than
    # replace it, so take the first value.
    def request_scheme(env)
      forwarded = env['HTTP_X_FORWARDED_PROTO'].to_s.split(',').first.to_s.strip
      return forwarded unless forwarded.empty?

      env['rack.url_scheme'] || 'https'
    end

    # The Host header, which includes the port when it is not the default, so a
    # non-standard port survives. SERVER_NAME is the fallback because Rack always sets it
    # while Host is only present when the client sent one; it carries no port, so a
    # hostless request on an odd port loses it, which is preferable to rewriting to the
    # wrong host entirely. Neither present means we cannot know the request's host, and
    # the response is left untouched.
    def request_host(env)
      host = env['HTTP_HOST']
      host = env['SERVER_NAME'] if host.nil? || host.to_s.empty?
      host&.to_s
    end
  end
end
