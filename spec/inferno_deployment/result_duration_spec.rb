require_relative '../../lib/inferno_platform_template/result_duration'

# Exercises the frame-stack attribution logic against a stand-in that reproduces the call
# structure ResultDurationPatch is prepended onto in Inferno::TestRunner: run_test and
# run_group both persist a result and then trigger a recursive parent roll-up, and
# run_group calls run_test for its children. The interesting behaviour is which of those
# writes gets a duration, which is independent of anything Inferno or the database do.
#
# Durations are compared loosely. Process::CLOCK_MONOTONIC in :millisecond truncates both
# endpoints, so a measured elapsed time is within a millisecond either side of the real
# one, and exact arithmetic on the values would be flaky.
# Defined outside the example group: constants assigned inside an RSpec block land on the
# example group class, which the anonymous Class.new bodies below cannot resolve.
SLEEP_SECONDS = 0.01
SLEEP_MS = 10

RSpec.describe InfernoPlatformTemplate::ResultDurationPatch do
  let(:runner_class) do
    Class.new do
      attr_reader :persisted

      def initialize
        @persisted = []
      end

      def run_test(test, _scratch = {})
        sleep SLEEP_SECONDS
        persist_result(name: test)
        update_parent_result("#{test}-parent")
      end

      def run_group(group, scratch = {})
        %w[child-a child-b].each { |child| run_test(child, scratch) }
        persist_result(name: group)
        update_parent_result("#{group}-parent")
      end

      # Mirrors TestRunner#update_parent_result recursing up the tree, persisting an
      # ancestor's recomputed result at each level.
      def update_parent_result(parent, depth = 2)
        return if depth.zero?

        persist_result(name: parent)
        update_parent_result("#{parent}-up", depth - 1)
      end

      def persist_result(params)
        @persisted << params
        params
      end
    end.tap { |klass| klass.prepend(described_class) }
  end

  let(:runner) { runner_class.new }

  def durations_by_name
    runner.persisted.to_h { |params| [params[:name], params[:duration_ms]] }
  end

  describe 'a single test' do
    before { runner.run_test('test-1') }

    it 'attributes a measured duration to the test' do
      expect(durations_by_name['test-1']).to be_a(Integer)
      expect(durations_by_name['test-1']).to be >= SLEEP_MS - 1
    end

    it 'leaves parent roll-ups without a duration' do
      roll_ups = runner.persisted.reject { |params| params[:name] == 'test-1' }

      expect(roll_ups).to_not be_empty
      expect(roll_ups.map { |params| params[:duration_ms] }).to all(be_nil)
    end
  end

  describe 'a group' do
    before { runner.run_group('group-1') }

    it 'times each child independently of the group' do
      expect(durations_by_name['child-a']).to be >= SLEEP_MS - 1
      expect(durations_by_name['child-b']).to be >= SLEEP_MS - 1
    end

    it "times the group across the whole of its children's execution" do
      # The bug this guards against is the group inheriting a child's frame, which would
      # report roughly one child's time rather than both.
      expect(durations_by_name['group-1']).to be >= (2 * SLEEP_MS) - 1
      expect(durations_by_name['group-1']).to be >= durations_by_name['child-a']
    end

    it 'does not let a child frame leak into the group roll-up' do
      expect(durations_by_name['group-1-parent']).to be_nil
    end
  end

  describe 'frame bookkeeping' do
    it 'unwinds every frame once a run completes' do
      runner.run_group('group-1')

      expect(runner.duration_frames).to be_empty
    end

    it 'unwinds the frame when the runnable raises' do
      # The raise has to come from the method the patch wraps, so it is defined on the
      # class the module is prepended onto. A singleton method would shadow the patch
      # instead of being called by it, and the test would prove nothing.
      raising_class = Class.new do
        def run_test(_test, _scratch = {})
          raise 'boom'
        end

        def persist_result(params) = params
      end
      raising_class.prepend(described_class)
      raising_runner = raising_class.new

      expect { raising_runner.run_test('test-1') }.to raise_error('boom')
      expect(raising_runner.duration_frames).to be_empty
    end

    it 'records no duration for a write outside any frame' do
      runner.persist_result(name: 'orphan')

      expect(durations_by_name['orphan']).to be_nil
    end
  end
end

# The unit tests above prove the attribution logic. These prove the patch actually binds to
# the inferno-core it is prepended onto, which is the part that breaks silently on a gem
# upgrade: a renamed method or a serializer that stops accepting a reopened field would
# leave duration_ms quietly absent rather than raising.
RSpec.describe 'result duration integration with inferno-core' do
  def result(attributes = {})
    Inferno::Entities::Result.new(
      { id: SecureRandom.uuid, result: 'pass', test_session_id: 'session', test_run_id: 'run' }
        .merge(attributes)
    )
  end

  it 'prepends the patch onto TestRunner' do
    expect(Inferno::TestRunner.ancestors).to include(InfernoPlatformTemplate::ResultDurationPatch)
  end

  it 'wraps the TestRunner methods it means to wrap' do
    owners = [:run_test, :run_group, :update_parent_result, :persist_result].to_h do |name|
      [name, Inferno::TestRunner.instance_method(name).owner]
    end

    expect(owners.values).to all(eq(InfernoPlatformTemplate::ResultDurationPatch))
  end

  it 'carries duration_ms through the Result entity' do
    expect(result(duration_ms: 1234).duration_ms).to eq(1234)
  end

  it 'leaves duration_ms nil when absent' do
    expect(result.duration_ms).to be_nil
  end

  it 'serializes duration_ms for the API' do
    rendered = Inferno::Web::Serializers::Result.render_as_hash(result(duration_ms: 1234))

    expect(rendered[:duration_ms]).to eq(1234)
  end

  it 'serializes a 0ms duration rather than dropping it as blank' do
    rendered = Inferno::Web::Serializers::Result.render_as_hash(result(duration_ms: 0))

    expect(rendered[:duration_ms]).to eq(0)
  end

  it 'omits duration_ms entirely when it was never recorded' do
    rendered = Inferno::Web::Serializers::Result.render_as_hash(result)

    expect(rendered).to_not have_key(:duration_ms)
  end
end
