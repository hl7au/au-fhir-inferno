require_relative '../../lib/inferno_platform_template/feedback_intake'

RSpec.describe InfernoPlatformTemplate::FeedbackIntake do
  let(:issue_client) { instance_double(described_class::GitHubIssueClient) }
  let(:limiter) { instance_double(described_class::RedisLimiter, allow?: true) }
  let(:inner_app) { ->(_env) { [200, { 'Content-Type' => 'text/plain' }, ['inner app']] } }
  let(:middleware) { described_class.new(inner_app, token: 'test-token', issue_client: issue_client, limiter: limiter) }
  let(:request) { Rack::MockRequest.new(middleware) }
  let(:session_id) { 'session-uuid' }
  let(:report) do
    {
      type: 'result', website: '', sessionId: session_id, suiteId: 'au_core_v200',
      suiteVersion: '1.4.6', kitVersion: '1.4.6',
      testId: 'au_core_v200-capability_statement-test',
      testName: '1.1.02 — FHIR Server supports the conformance interaction',
      outcome: 'fail', resultTime: '2026-09-25T02:36:58.561+00:00',
      feedbackTime: '2026-09-25T03:03:37.440Z',
      expected: 'A clearer explanation.', actual: 'The result was confusing.',
      identity: 'anonymous', name: '', email: '', publishContact: false
    }
  end

  def submit(payload = report, origin: 'http://example.org', path: described_class::PATH)
    request.post(path, 'CONTENT_TYPE' => 'application/json',
                                        'HTTP_ORIGIN' => origin,
                                        input: JSON.generate(payload))
  end

  it 'previews the exact public context without creating an issue' do
    expect(issue_client).not_to receive(:create)
    preview = JSON.parse(submit(report, path: described_class::PREVIEW_PATH).body)
    expect(preview['title']).to include('1.1.02')
    expect(preview['context']).to include('Result time (UTC): 2026-09-25T02:36:58.561+00:00')
    expect(preview['context']).not_to include(session_id)
    expect(preview['reporter']).to eq('Anonymous community member')
  end

  it 'creates a public issue without a GitHub login or raw session data' do
    expect(issue_client).to receive(:create) do |title:, body:|
      expect(title).to eq('AU Inferno result feedback: 1.1.02 — FHIR Server supports the conformance interaction')
      expect(body).to include('Reporter:** Anonymous community member')
      expect(body).to include('Test ID: au_core_v200-capability_statement-test')
      expect(body).to include('Feedback reference: fb-cbbda06044deb94958ff5bb9')
      expect(body).to include('A clearer explanation.')
      expect(body).not_to include(session_id)
      'https://github.com/hl7au/au-fhir-inferno/issues/123'
    end

    response = submit
    expect(response.status).to eq(201)
    expect(JSON.parse(response.body)['url']).to eq('https://github.com/hl7au/au-fhir-inferno/issues/123')
  end

  it 'includes contact details only when explicitly selected and acknowledged' do
    named = report.merge(identity: 'named', name: 'Pat Example', email: 'pat@example.org', publishContact: true)
    expect(issue_client).to receive(:create) do |body:, **|
      expect(body).to include('Pat Example')
      expect(body).to include('Contact email (public): pat@example.org')
      'https://github.com/hl7au/au-fhir-inferno/issues/124'
    end
    expect(submit(named).status).to eq(201)
    expect(submit(named.merge(publishContact: false)).status).to eq(422)
  end

  it 'rejects a full session URL and requires the same origin' do
    expect(submit(report.merge(actual: "See https://example.org/suites/au_core_v200/#{session_id}")).status).to eq(422)
    expect(submit(report, origin: 'https://elsewhere.example')).to have_attributes(status: 403)
  end

  it 'enforces the shared rate limit before creating an issue' do
    allow(limiter).to receive(:allow?).and_return(false)
    expect(issue_client).not_to receive(:create)
    expect(submit.status).to eq(429)
  end

  it 'advertises when the dedicated credential has not been provisioned' do
    unconfigured = described_class.new(inner_app, token: '')
    client = Rack::MockRequest.new(unconfigured)
    expect(JSON.parse(client.get(described_class::CONFIG_PATH).body)).to eq('enabled' => false)
    expect(client.post(described_class::PATH).status).to eq(503)
    preview = client.post(described_class::PREVIEW_PATH, 'CONTENT_TYPE' => 'application/json',
                                                        'HTTP_ORIGIN' => 'http://example.org',
                                                        input: JSON.generate(report))
    expect(preview.status).to eq(200)
  end

  it 'sends only title and body to the GitHub issue endpoint' do
    url = 'https://github.com/hl7au/au-fhir-inferno/issues/125'
    stub = stub_request(:post, 'https://api.github.com/repos/hl7au/au-fhir-inferno/issues')
      .with(headers: { 'Authorization' => 'Bearer test-token' })
      .to_return(status: 201, body: JSON.generate(html_url: url))

    result = described_class::GitHubIssueClient.new('test-token').create(title: 'Title', body: 'Body')
    expect(result).to eq(url)
    expect(stub).to have_been_requested.once
  end
end
