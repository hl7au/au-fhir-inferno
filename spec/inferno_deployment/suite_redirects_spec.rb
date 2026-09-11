# Guards the /suites -> /test-kits redirects that replaced the nginx `rewrite` rules.
#
# Two failure modes matter, and they pull in opposite directions. Under-matching is what
# the nginx version actually did: its `au_core_v\d+(_ballot)?` regex missed
# au_core_v300_ballot1, the suite this platform currently leads with, so backing out of a
# session landed on the bare suite page. Over-matching is worse: taking over a
# multi-segment path under /suites breaks session pages, the API or session creation
# outright. Both directions are asserted here, and the mapping itself is checked against
# the site content so it cannot drift from the pages it points at.
require 'yaml'
require_relative '../../lib/inferno_platform_template/suite_redirects'

RSpec.describe InfernoPlatformTemplate::SuiteRedirects do
  let(:inner_app) do
    ->(_env) { [200, { 'Content-Type' => 'text/plain' }, ['inner app']] }
  end

  let(:request) { Rack::MockRequest.new(described_class.new(inner_app)) }

  describe 'the suite index' do
    it 'redirects /suites to the test kit list' do
      response = request.get('/suites')

      expect(response.status).to eq(302)
      expect(response['Location']).to eq('/test-kits/')
    end

    it 'redirects /suites/ the same way' do
      expect(request.get('/suites/')['Location']).to eq('/test-kits/')
    end
  end

  describe 'suite landing pages' do
    it 'redirects an AU Core suite to the AU Core kit page' do
      response = request.get('/suites/au_core_v300_ballot1')

      expect(response.status).to eq(302)
      expect(response['Location']).to eq('/test-kits/au-core/')
    end

    it 'redirects an AU PS suite to the AU PS kit page' do
      expect(request.get('/suites/au_ps_v100')['Location']).to eq('/test-kits/au-ps/')
    end

    it 'tolerates a trailing slash' do
      expect(request.get('/suites/au_core_v200/')['Location']).to eq('/test-kits/au-core/')
    end

    it 'answers HEAD as well as GET' do
      expect(request.head('/suites/au_ps_v100').status).to eq(302)
    end
  end

  describe 'paths that belong to Inferno' do
    # Every one of these is a live Inferno route. A redirect on any of them is an outage,
    # not a cosmetic bug.
    it 'never touches a session page' do
      expect(request.get('/suites/au_core_v300_ballot1/abc').body).to eq('inner app')
    end

    it 'never touches the API' do
      expect(request.get('/suites/api/test_suites').body).to eq('inner app')
      expect(request.get('/suites/api/version').body).to eq('inner app')
    end

    it 'never touches session creation' do
      expect(request.get('/suites/test_sessions/x').body).to eq('inner app')
    end

    it 'never touches custom pages or bundled assets' do
      expect(request.get('/suites/custom/thing').body).to eq('inner app')
      expect(request.get('/suites/public/bundle.js').body).to eq('inner app')
    end

    it 'leaves an unknown suite id to Inferno' do
      expect(request.get('/suites/smart_app_launch').body).to eq('inner app')
    end

    it 'leaves the static site alone' do
      expect(request.get('/').body).to eq('inner app')
      expect(request.get('/test-kits/au-core/').body).to eq('inner app')
    end

    it 'ignores anything that is not GET or HEAD' do
      expect(request.post('/suites/test_sessions').body).to eq('inner app')
    end
  end

  # The mapping is a prefix table, and the site pages it points at are generated from
  # web/_test_kits/*.md. If a kit gains a suite whose id does not start with a known
  # prefix (a new kit, or an id renamed), the redirect silently stops working for it.
  # Reading the site content is the only check that catches that.
  describe 'coverage of every suite the site advertises' do
    kit_files = Dir[File.expand_path('../../web/_test_kits/*.md', __dir__)]

    it 'finds the test kit content' do
      expect(kit_files).to_not be_empty
    end

    kit_files.each do |kit_file|
      # Front matter only: the body after the closing --- is HTML, not YAML.
      front_matter = YAML.safe_load(File.read(kit_file).split(/^---\s*$/)[1], permitted_classes: [Date])
      page = "/test-kits/#{File.basename(kit_file, '.md')}/"

      (front_matter['suites'] || []).each do |suite|
        suite_id = suite['id'].to_s.strip

        it "redirects #{suite_id} to #{page}" do
          expect(request.get("/suites/#{suite_id}")['Location']).to eq(page)
        end
      end
    end
  end
end
