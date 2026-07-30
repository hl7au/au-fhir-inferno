require 'opentelemetry/sdk'

# PerTestTraceRoot is defined inside an `if ENV['OTEL_EXPORTER_OTLP_ENDPOINT']` guard, so the
# env var has to be set before the file is evaluated.
ENV['OTEL_EXPORTER_OTLP_ENDPOINT'] ||= 'http://localhost:4318'
require_relative '../../lib/inferno_platform_template/test_tracing'

# Plain stubs rather than RSpec doubles: these are constructed inside the stand-in runner's
# method bodies, where example-scope helpers like `double` are not available.
TraceRunStub = Struct.new(:id)
TraceSessionStub = Struct.new(:id, :test_suite_id)
TraceResultStub = Struct.new(:result)
TraceTestStub = Struct.new(:id, :short_id, :title, :suite, :parent, keyword_init: true) do
  # Mirrors Runnable#suite raising when the runnable is not mounted under a TestSuite.
  def suite
    raise NoMethodError, "undefined method 'suite' for nil" if self[:suite] == :raises

    self[:suite]
  end
end
TraceSuiteStub = Struct.new(:id)
TraceGroupStub = Struct.new(:id)

RSpec.describe PerTestTraceRoot do
  # A local tracer provider, injected by stubbing OpenTelemetry.tracer_provider, rather than
  # OpenTelemetry::SDK.configure. Configuring the SDK replaces the global provider, which
  # would fight with any other spec that does the same under random ordering.
  let(:exporter) { OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new }
  let(:provider) do
    OpenTelemetry::SDK::Trace::TracerProvider.new.tap do |p|
      p.add_span_processor(OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(exporter))
    end
  end

  before { allow(OpenTelemetry).to receive(:tracer_provider).and_return(provider) }

  # Stands in for TestRunner: supplies the run and session the patch reads, and a #run_test
  # whose return value is the persisted result, as the real one's is.
  let(:runner_class) do
    Class.new do
      attr_accessor :test_run, :test_session, :next_result, :persist_params

      def run_test(_test, _scratch = {})
        persist_result(@persist_params) if @persist_params
        @next_result
      end

      def persist_result(_params)
        :persisted
      end

      def start
        :started
      end
    end.tap { |k| k.prepend(described_class) }
  end

  let(:runner) do
    runner_class.new.tap do |r|
      r.test_run = TraceRunStub.new('run-uuid')
      r.test_session = TraceSessionStub.new('session-uuid', 'au_core_v210_draft')
      r.next_result = TraceResultStub.new('pass')
    end
  end

  def build_test(**overrides)
    TraceTestStub.new(
      **{
        id: 'au_core_v210_draft-patient_group-patient_read_test',
        short_id: '1.2.03',
        title: 'Server returns a Patient',
        suite: TraceSuiteStub.new('au_core_v210_draft'),
        parent: TraceGroupStub.new('au_core_v210_draft-patient_group')
      }.merge(overrides)
    )
  end

  def run(outcome: 'pass', test: build_test)
    runner.next_result = TraceResultStub.new(outcome)
    runner.run_test(test, {})
    exporter.finished_spans
  end

  describe 'span naming' do
    it 'uses a constant name so span_name does not become a per-test metrics dimension' do
      expect(run.map(&:name)).to eq(['inferno.test'])
    end

    it 'keeps the test id out of the name entirely' do
      expect(run.first.name).to_not include('patient_read_test')
    end
  end

  describe 'identity attributes' do
    subject(:attributes) { run.first.attributes }

    it 'carries the ids needed to find a span from a session or a run' do
      expect(attributes['inferno.test_run_id']).to eq('run-uuid')
      expect(attributes['inferno.test_session_id']).to eq('session-uuid')
    end

    it 'carries what identifies the test itself' do
      expect(attributes['inferno.test_id']).to eq('au_core_v210_draft-patient_group-patient_read_test')
      expect(attributes['inferno.test_short_id']).to eq('1.2.03')
      expect(attributes['inferno.test_title']).to eq('Server returns a Patient')
    end

    it 'carries the suite and group, so spans can be aggregated by either' do
      expect(attributes['inferno.suite_id']).to eq('au_core_v210_draft')
      expect(attributes['inferno.group_id']).to eq('au_core_v210_draft-patient_group')
    end
  end

  describe 'when identity is not fully available' do
    it 'omits absent attributes rather than exporting nils' do
      attributes = run(test: build_test(short_id: nil, parent: nil)).first.attributes

      expect(attributes).to_not have_key('inferno.test_short_id')
      expect(attributes).to_not have_key('inferno.group_id')
      expect(attributes['inferno.test_id']).to_not be_nil
    end

    it 'still emits the span when the suite cannot be resolved' do
      spans = run(test: build_test(suite: :raises))

      expect(spans.size).to eq(1)
      expect(spans.first.attributes).to_not have_key('inferno.suite_id')
    end
  end

  describe 'result annotation' do
    it 'records the outcome on the span' do
      expect(run(outcome: 'fail').first.attributes['inferno.result']).to eq('fail')
    end

    it 'leaves a failing test unset, because a conformance failure is not a system error' do
      expect(run(outcome: 'fail').first.status.code).to_not eq(OpenTelemetry::Trace::Status::ERROR)
    end

    it 'marks an errored test as a span error' do
      expect(run(outcome: 'error').first.status.code).to eq(OpenTelemetry::Trace::Status::ERROR)
    end

    it 'tolerates a result that carries no outcome' do
      runner.next_result = Object.new

      expect { runner.run_test(build_test, {}) }.to_not raise_error
      expect(exporter.finished_spans.first.attributes).to_not have_key('inferno.result')
    end

    it 'tolerates a nil outcome' do
      expect { run(outcome: nil) }.to_not raise_error
    end
  end

  describe 'the result-persistence span' do
    # Two messages and three requests, which is all the patch reads from the params.
    let(:params) { { messages: [{}, {}], requests: [{}, {}, {}] } }

    before { runner.persist_params = params }

    def persist_span
      run.find { |span| span.name == 'inferno.persist_result' }
    end

    it 'emits a span for the write' do
      expect(run.map(&:name)).to contain_exactly('inferno.persist_result', 'inferno.test')
    end

    it 'nests it inside the test span, so it inherits that test identity' do
      spans = run
      test_span = spans.find { |span| span.name == 'inferno.test' }
      persist = spans.find { |span| span.name == 'inferno.persist_result' }

      expect(persist.parent_span_id).to eq(test_span.span_id)
      expect(persist.trace_id).to eq(test_span.trace_id)
    end

    it 'records the row counts that explain the cost' do
      expect(persist_span.attributes['inferno.messages_persisted']).to eq(2)
      expect(persist_span.attributes['inferno.requests_persisted']).to eq(3)
    end

    it 'reports zero rather than omitting the counts when there is nothing to write' do
      runner.persist_params = { result: 'pass' }

      expect(persist_span.attributes['inferno.messages_persisted']).to eq(0)
      expect(persist_span.attributes['inferno.requests_persisted']).to eq(0)
    end

    it 'passes the persisted result through unchanged' do
      expect(runner.persist_result(params)).to eq(:persisted)
    end
  end

  # The methods this patch wraps are called from outside the runner: Jobs::ExecuteTestRun
  # calls #start, and #persist_result is public API on TestRunner. A `private` placed above
  # a wrapper in the module would make the wrapped method private on TestRunner too, and
  # the failure would only surface when a real run started.
  describe 'visibility of the wrapped methods' do
    it 'leaves them public on TestRunner' do
      expect(Inferno::TestRunner.public_instance_methods)
        .to include(:start, :run_test, :persist_result)
    end
  end

  describe 'returning the result' do
    it 'passes the runner result through unchanged' do
      sentinel = TraceResultStub.new('pass')
      runner.next_result = sentinel

      expect(runner.run_test(build_test, {})).to be(sentinel)
    end
  end

  describe 'trace shape' do
    it 'starts a new trace per test rather than nesting under the caller' do
      tracer = provider.tracer('outer')
      test_trace_id = nil
      job_trace_id = nil

      tracer.in_span('default process') do |job_span|
        run
        test_trace_id = exporter.finished_spans.first.trace_id
        job_trace_id = job_span.context.trace_id
      end

      expect(test_trace_id).to_not eq(job_trace_id)
    end

    it 'emits the test span with no parent' do
      expect(run.first.parent_span_id).to eq(OpenTelemetry::Trace::INVALID_SPAN_ID)
    end
  end

  describe 'annotating the enclosing run span' do
    it 'adds run identity to whatever span is current' do
      provider.tracer('sidekiq').in_span('default process') { runner.start }
      job_span = exporter.finished_spans.find { |s| s.name == 'default process' }

      expect(job_span.attributes['inferno.test_run_id']).to eq('run-uuid')
      expect(job_span.attributes['inferno.test_session_id']).to eq('session-uuid')
      expect(job_span.attributes['inferno.suite_id']).to eq('au_core_v210_draft')
    end

    it 'does not create a run span of its own' do
      provider.tracer('sidekiq').in_span('default process') { runner.start }

      expect(exporter.finished_spans.map(&:name)).to eq(['default process'])
    end

    it 'is harmless when there is no active span' do
      expect { runner.start }.to_not raise_error
      expect(exporter.finished_spans).to be_empty
    end

    it 'still runs the wrapped method' do
      expect(runner.start).to eq(:started)
    end
  end
end
