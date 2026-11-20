# Guards /site-config.json, the runtime facts the kit pages read.
#
# What matters: production must report no ci-build host (so it shows no CI-build radio),
# a malformed host must never reach the page as a form target, and the CI-build suites
# listed must be exactly the ones the environment registers, by the fixed-id suffix.
require 'json'
require_relative '../../lib/inferno_platform_template/site_config'

RSpec.describe InfernoPlatformTemplate::SiteConfig do
  let(:inner_app) do
    ->(_env) { [200, { 'Content-Type' => 'text/plain' }, ['inner app']] }
  end

  suite = Struct.new(:id, :title)
  let(:released_suites) { [suite.new('au_ps_v100', 'AU PS 1.0.0 Test Suite'), suite.new('au_core_v200', 'AU Core v2.0.0')] }
  let(:ci_suite) { suite.new('au_ps_ci_build', 'AU PS 1.1.0-ci-build Test Suite (tracks the CI build)') }

  def request_for(host: '', suites: released_suites)
    Rack::MockRequest.new(described_class.new(inner_app, ci_build_host: host, suites:))
  end

  def config_from(response)
    JSON.parse(response.body)
  end

  describe 'on production (no host, no CI-build suites)' do
    it 'reports a null host and no CI-build suites' do
      response = request_for.get('/site-config.json')

      expect(response.status).to eq(200)
      expect(config_from(response)).to eq('ciBuildHost' => nil, 'ciBuildSuites' => [])
    end
  end

  describe 'on staging (host set, no CI-build suites of its own)' do
    it 'reports the host' do
      response = request_for(host: 'https://ci-build.inferno.sparked-fhir.com').get('/site-config.json')

      expect(config_from(response)['ciBuildHost']).to eq('https://ci-build.inferno.sparked-fhir.com')
    end
  end

  describe 'on the ci-build environment' do
    it 'lists only the suites with the fixed CI-build suffix, with their registered titles' do
      response = request_for(suites: released_suites + [ci_suite]).get('/site-config.json')

      expect(config_from(response)['ciBuildSuites']).to eq(
        [{ 'id' => 'au_ps_ci_build', 'title' => 'AU PS 1.1.0-ci-build Test Suite (tracks the CI build)' }]
      )
    end
  end

  describe 'host validation' do
    [
      'http://ci-build.inferno.sparked-fhir.com',
      'http://localhost.evil.example',
      'https://ci-build.inferno.sparked-fhir.com/',
      'https://ci-build.inferno.sparked-fhir.com/suites',
      'https://evil.example/" onload="x',
      'javascript:alert(1)',
      'ci-build.inferno.sparked-fhir.com'
    ].each do |bad|
      it "reports null rather than #{bad.inspect}" do
        expect(config_from(request_for(host: bad).get('/site-config.json'))['ciBuildHost']).to be_nil
      end
    end

    it 'accepts plain-http localhost, for two local instances' do
      expect(config_from(request_for(host: 'http://localhost:4568').get('/site-config.json'))['ciBuildHost'])
        .to eq('http://localhost:4568')
    end

    it 'accepts an explicit port' do
      host = 'https://localhost:8443'

      expect(config_from(request_for(host:).get('/site-config.json'))['ciBuildHost']).to eq(host)
    end

    it 'reads INFERNO_CI_BUILD_HOST when no override is given' do
      app = described_class.new(inner_app, suites: [])
      original = ENV.fetch('INFERNO_CI_BUILD_HOST', nil)
      ENV['INFERNO_CI_BUILD_HOST'] = 'https://ci-build.example.org'

      expect(config_from(Rack::MockRequest.new(app).get('/site-config.json'))['ciBuildHost'])
        .to eq('https://ci-build.example.org')
    ensure
      original.nil? ? ENV.delete('INFERNO_CI_BUILD_HOST') : ENV['INFERNO_CI_BUILD_HOST'] = original
    end
  end

  describe 'response headers' do
    let(:response) { request_for.get('/site-config.json') }

    it 'is JSON' do
      expect(response['Content-Type']).to eq('application/json')
    end

    # Staging's kit page reads the ci-build host's copy cross-origin.
    it 'allows any origin to read it' do
      expect(response['Access-Control-Allow-Origin']).to eq('*')
    end

    it 'answers HEAD with no body' do
      head = request_for.head('/site-config.json')

      expect(head.status).to eq(200)
      expect(head.body).to be_empty
    end
  end

  describe 'everything else' do
    it 'passes other paths through' do
      expect(request_for.get('/site-config.json.bak').body).to eq('inner app')
      expect(request_for.get('/suites/api/test_suites').body).to eq('inner app')
    end

    it 'passes other methods through' do
      expect(request_for.post('/site-config.json').body).to eq('inner app')
    end
  end
end
