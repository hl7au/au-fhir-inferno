# Guards the Location rewrite that replaced nginx's proxy_redirect.
#
# Two opposite mistakes are both serious. Failing to rewrite sends a user mid-flow to
# whichever hostname INFERNO_HOST happens to name, which under build-once means a preview
# hands its user to DEV. Rewriting too eagerly is worse: a test kit can redirect to an
# authorization server, and moving the host of an OAuth redirect breaks the flow and can
# point a code-bearing URL somewhere it does not belong. Every condition that separates
# the two is asserted here.
require_relative '../../lib/inferno_platform_template/request_host_redirects'

RSpec.describe InfernoPlatformTemplate::RequestHostRedirects do
  let(:configured_host) { 'https://inferno.example.org' }
  let(:base_path) { 'suites' }

  # Passed in rather than stubbed: Inferno::Application is a frozen container once
  # finalised, and a spec reading the ambient .env would assert whatever this machine is
  # configured for rather than the behaviour.
  def middleware(inner)
    described_class.new(inner, inferno_host: configured_host, base_path: base_path)
  end

  def location_for(location, path: '/suites/au_core_v300_ballot1', **headers)
    inner = ->(_env) { [302, { 'Location' => location }, []] }
    env = Rack::MockRequest.env_for("http://request.example.test#{path}", method: 'POST')
    env['HTTP_HOST'] = 'request.example.test'
    headers.each { |key, value| value.nil? ? env.delete(key.to_s) : env[key.to_s] = value }

    _status, response_headers, _body = middleware(inner).call(env)
    response_headers['Location']
  end

  describe 'redirects Inferno builds from INFERNO_HOST' do
    # The shape the session form POST and the session show route actually emit.
    it 'moves a session redirect onto the request host' do
      rewritten = location_for("#{configured_host}/suites/au_core_v300_ballot1/abc-123")

      expect(rewritten).to eq('http://request.example.test/suites/au_core_v300_ballot1/abc-123')
    end

    it 'preserves the query string' do
      rewritten = location_for("#{configured_host}/suites/test_sessions/abc?preset_id=xyz")

      expect(rewritten).to eq('http://request.example.test/suites/test_sessions/abc?preset_id=xyz')
    end

    it 'matches the configured origin regardless of case' do
      rewritten = location_for('https://INFERNO.EXAMPLE.ORG/suites/au_ps_v100/abc')

      expect(rewritten).to eq('http://request.example.test/suites/au_ps_v100/abc')
    end

    it 'treats an explicit default port as the same origin' do
      rewritten = location_for('https://inferno.example.org:443/suites/au_ps_v100/abc')

      expect(rewritten).to eq('http://request.example.test/suites/au_ps_v100/abc')
    end
  end

  describe 'the scheme it redirects to' do
    # TLS terminates at the gateway, so rack.url_scheme on the wire is always http and
    # only the forwarded header knows what the client used. Getting this wrong downgrades
    # a user to http mid-session.
    it 'prefers X-Forwarded-Proto over rack.url_scheme' do
      rewritten = location_for("#{configured_host}/suites/au_ps_v100/abc",
                               HTTP_X_FORWARDED_PROTO: 'https')

      expect(rewritten).to eq('https://request.example.test/suites/au_ps_v100/abc')
    end

    it 'takes the first value when a proxy chain appended to the header' do
      rewritten = location_for("#{configured_host}/suites/au_ps_v100/abc",
                               HTTP_X_FORWARDED_PROTO: 'https, http')

      expect(rewritten).to eq('https://request.example.test/suites/au_ps_v100/abc')
    end

    it 'falls back to the scheme of the request itself' do
      rewritten = location_for("#{configured_host}/suites/au_ps_v100/abc")

      expect(rewritten).to start_with('http://')
    end
  end

  describe 'redirects it must never touch' do
    it 'leaves an external host alone, which is what makes OAuth safe' do
      location = 'https://auth.example.com/authorize?client_id=inferno&state=abc'

      expect(location_for(location)).to eq(location)
    end

    it 'leaves a relative Location alone' do
      expect(location_for('/test-kits/au-core/')).to eq('/test-kits/au-core/')
    end

    it 'leaves our own host alone outside the inferno base path' do
      location = "#{configured_host}/some-other-app/callback"

      expect(location_for(location)).to eq(location)
    end

    it 'does not treat a path that merely starts with the same letters as inferno-owned' do
      location = "#{configured_host}/suitesomething/else"

      expect(location_for(location)).to eq(location)
    end

    it 'leaves a different port on our host alone' do
      location = "#{configured_host}:8443/suites/au_ps_v100/abc"

      expect(location_for(location)).to eq(location)
    end

    it 'leaves a different scheme on our host alone' do
      location = 'http://inferno.example.org/suites/au_ps_v100/abc'

      expect(location_for(location)).to eq(location)
    end

    it 'leaves the response untouched when the request carries no host at all' do
      location = "#{configured_host}/suites/au_ps_v100/abc"

      expect(location_for(location, HTTP_HOST: nil, SERVER_NAME: nil)).to eq(location)
    end

    it 'adds no Location to a response that had none' do
      inner = ->(_env) { [200, { 'Content-Type' => 'text/plain' }, ['ok']] }
      _status, headers, _body = middleware(inner).call(Rack::MockRequest.env_for('/suites'))

      expect(headers).to_not have_key('Location')
    end
  end

  describe 'header casing' do
    # Nothing enforces Rack 2's capitalisation convention, and a lowercase key that went
    # unrewritten would fail silently.
    it 'rewrites a lowercase location header in place' do
      inner = ->(_env) { [302, { 'location' => "#{configured_host}/suites/au_ps_v100/abc" }, []] }
      env = Rack::MockRequest.env_for('http://request.example.test/suites/au_ps_v100')
      env['HTTP_HOST'] = 'request.example.test'

      _status, headers, _body = middleware(inner).call(env)

      expect(headers['location']).to eq('http://request.example.test/suites/au_ps_v100/abc')
      expect(headers).to_not have_key('Location')
    end
  end

  describe 'when inferno is mounted at the root' do
    # BASE_PATH is empty in some deployments, so there is no /suites prefix to test and
    # every path on our own origin belongs to inferno.
    let(:base_path) { '' }

    it 'rewrites any redirect to our own origin' do
      rewritten = location_for("#{configured_host}/au_ps_v100/abc")

      expect(rewritten).to eq('http://request.example.test/au_ps_v100/abc')
    end
  end
end
