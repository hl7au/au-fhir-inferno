# Guards the middleware that replaced the nginx layer's static file serving. The failure
# modes worth catching are all silent: a path that escapes the root, a directory served
# without its trailing-slash redirect (which breaks every relative link on a Jekyll
# page), a cache header applied to the wrong class of file, or the middleware swallowing
# a request that belongs to Inferno.
require 'tmpdir'
require_relative '../../lib/inferno_platform_template/static_site'

RSpec.describe InfernoPlatformTemplate::StaticSite do
  let(:root) { Dir.mktmpdir('static-site-spec') }

  # Distinguishable from anything the middleware itself returns, so "fell through" is an
  # unambiguous assertion.
  let(:inner_app) do
    ->(_env) { [200, { 'Content-Type' => 'text/plain' }, ['inner app'] ] }
  end

  let(:middleware) { described_class.new(inner_app, root: root) }
  let(:request) { Rack::MockRequest.new(middleware) }

  def write(relative_path, content)
    full_path = File.join(root, relative_path)
    FileUtils.mkdir_p(File.dirname(full_path))
    File.write(full_path, content)
  end

  before do
    write('index.html', '<html>home</html>')
    write('about/index.html', '<html>about</html>')
    write('assets/images/checklist.svg', '<svg/>')
  end

  after { FileUtils.remove_entry(root) }

  describe 'serving files' do
    it 'serves a file with the mime type its extension implies' do
      response = request.get('/assets/images/checklist.svg')

      expect(response.status).to eq(200)
      expect(response['Content-Type']).to eq('image/svg+xml')
      expect(response.body).to eq('<svg/>')
    end

    it 'serves the root index page' do
      response = request.get('/')

      expect(response.status).to eq(200)
      expect(response['Content-Type']).to eq('text/html')
      expect(response.body).to eq('<html>home</html>')
    end

    it 'answers HEAD with the headers and no body' do
      response = request.head('/assets/images/checklist.svg')

      expect(response.status).to eq(200)
      expect(response['Content-Type']).to eq('image/svg+xml')
      expect(response.body).to be_empty
    end

    it 'sets Last-Modified, so conditional requests still work without nginx' do
      response = request.get('/assets/images/checklist.svg')

      expect(response['Last-Modified']).to_not be_nil
    end
  end

  describe 'cache headers' do
    # Mirrors the nginx.conf $cacheable map. Getting this backwards is invisible until a
    # content deploy fails to appear for a day.
    it 'gives cacheable asset types a day of browser caching' do
      response = request.get('/assets/images/checklist.svg')

      expect(response['Cache-Control']).to eq('public, max-age=86400')
    end

    it 'makes generated pages revalidate every time' do
      response = request.get('/')

      expect(response['Cache-Control']).to eq('no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0')
    end

    it 'leaves headers alone on responses it passes through' do
      response = request.get('/suites/api/version')

      expect(response.body).to eq('inner app')
      expect(response['Cache-Control']).to be_nil
    end
  end

  describe 'directories' do
    it 'redirects a directory request to its trailing-slash form' do
      response = request.get('/about')

      expect(response.status).to eq(301)
      expect(response['Location']).to eq('/about/')
    end

    it 'serves index.html once the path has its trailing slash' do
      response = request.get('/about/')

      expect(response.status).to eq(200)
      expect(response.body).to eq('<html>about</html>')
    end

    it 'passes through a directory with no index.html' do
      FileUtils.mkdir_p(File.join(root, 'empty'))

      expect(request.get('/empty/').body).to eq('inner app')
    end
  end

  describe 'requests it must not answer' do
    it 'passes through a path with no matching file' do
      expect(request.get('/nothing-here').body).to eq('inner app')
    end

    it 'passes through Inferno paths' do
      expect(request.get('/suites/au_core_v300_ballot1/abc').body).to eq('inner app')
      expect(request.get('/suites').body).to eq('inner app')
    end

    it 'passes through the health endpoints' do
      expect(request.get('/healthz/ready').body).to eq('inner app')
    end

    it 'passes through anything that is not GET or HEAD' do
      expect(request.post('/').body).to eq('inner app')
    end
  end

  describe 'path traversal' do
    # clean_path_info normalises '..' away rather than rejecting it, so a traversal
    # attempt becomes a lookup of an absolute path UNDER the root, which does not exist.
    it 'cannot read a file outside the root' do
      secret = File.join(File.dirname(root), 'outside-the-root.txt')
      File.write(secret, 'secret')

      begin
        %w[/../outside-the-root.txt /assets/../../outside-the-root.txt /%2e%2e/outside-the-root.txt]
          .each do |path|
            response = request.get(path)

            expect(response.body).to_not include('secret')
          end
      ensure
        FileUtils.rm_f(secret)
      end
    end

    it 'still serves a path that merely contains a resolvable dot segment' do
      response = request.get('/assets/images/../images/checklist.svg')

      expect(response.status).to eq(200)
      expect(response.body).to eq('<svg/>')
    end
  end

  describe 'a missing site root' do
    # _site is gitignored and generated, so a fresh checkout has none. The app must still
    # boot and serve Inferno rather than failing at require time or 500ing on every page.
    it 'is a pass-through' do
      middleware = described_class.new(inner_app, root: File.join(root, 'does-not-exist'))

      expect(Rack::MockRequest.new(middleware).get('/').body).to eq('inner app')
    end
  end

  describe 'root resolution' do
    it 'reads STATIC_SITE_ROOT when no root is passed' do
      previous = ENV.fetch('STATIC_SITE_ROOT', nil)
      ENV['STATIC_SITE_ROOT'] = root

      begin
        response = Rack::MockRequest.new(described_class.new(inner_app)).get('/')

        expect(response.body).to eq('<html>home</html>')
      ensure
        ENV['STATIC_SITE_ROOT'] = previous
      end
    end
  end
end
