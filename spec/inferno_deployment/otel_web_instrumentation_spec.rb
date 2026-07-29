# Guards the web process's OpenTelemetry wiring, which is easy to break silently: config.ru
# resolves the Rack middleware through the instrumentation's `middleware_args` rather than a
# constant, because 0.31 splits the handler three ways by HTTP semantic-convention
# stability. If a gem upgrade changes that entry point, or the handler stops producing a
# server span, tracing for inbound requests just stops and nothing raises.
require 'opentelemetry/sdk'
require 'opentelemetry/instrumentation/rack'

RSpec.describe 'web process OpenTelemetry instrumentation' do
  # Configured once for the whole file. The tracer provider is global, so repeatedly
  # reconfiguring it across examples would leak between them.
  before(:all) do
    # Without this the SDK adds a default OTLP exporter that tries to reach
    # localhost:4318, which WebMock blocks.
    @previous_exporter = ENV.fetch('OTEL_TRACES_EXPORTER', nil)
    ENV['OTEL_TRACES_EXPORTER'] = 'none'

    @exporter = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
    OpenTelemetry::SDK.configure do |c|
      c.service_name = 'inferno-app'
      c.add_span_processor(OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(@exporter))
      c.use 'OpenTelemetry::Instrumentation::Rack'
    end
  end

  after(:all) do
    ENV['OTEL_TRACES_EXPORTER'] = @previous_exporter
  end

  before { @exporter.reset }

  # The same expression config.ru uses.
  let(:middleware_args) { OpenTelemetry::Instrumentation::Rack::Instrumentation.instance.middleware_args }

  let(:app) do
    args = middleware_args
    Rack::Builder.new do
      use(*args)
      run ->(_env) { [200, { 'content-type' => 'text/plain' }, ['ok']] }
    end.to_app
  end

  # Rack::Events finishes the span in on_finish, which a server triggers by closing the
  # response body. Puma does this; calling the app directly does not.
  def get(path)
    _status, _headers, body = app.call(Rack::MockRequest.env_for(path, method: 'POST'))
    body.each { |_chunk| } if body.respond_to?(:each)
    body.close if body.respond_to?(:close)
  end

  it 'resolves a usable middleware from the instrumentation' do
    expect(middleware_args).to_not be_empty
  end

  it 'emits exactly one span per request' do
    get('/test_sessions')

    expect(@exporter.finished_spans.size).to eq(1)
  end

  it 'emits a server span, so inbound requests can parent their outbound calls' do
    get('/test_sessions')

    expect(@exporter.finished_spans.first.kind).to eq(:server)
  end

  it 'attributes the span to the configured service' do
    get('/test_sessions')

    service = @exporter.finished_spans.first.resource.attribute_enumerator.to_h['service.name']

    expect(service).to eq('inferno-app')
  end

  it 'records the request path, which is what makes session creation findable' do
    get('/test_sessions?test_suite_id=au_core_v210_draft')

    attributes = @exporter.finished_spans.first.attributes

    expect(attributes['url.path']).to eq('/test_sessions')
    expect(attributes['http.request.method']).to eq('POST')
    expect(attributes['http.response.status_code']).to eq(200)
  end
end
