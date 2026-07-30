require_relative '../../lib/inferno_platform_template/result_duration'

# Exercises the frame-stack attribution logic against a stand-in that reproduces the call
# structure ResultDurationPatch is prepended onto in Inferno::TestRunner: run_test and
# run_group both persist a result and then trigger a recursive parent roll-up, and
# run_group calls run_test for its children. The interesting behaviour is which of those
# writes gets a duration, which is independent of anything Inferno or the database do.
#
# The stand-in sleeps inside persist_result as well as inside the runnable, because the two
# are measured differently: a result row cannot carry the cost of writing itself, so the
# patch inserts the execution time and then updates the row with the total. Separating the
# sleeps is what makes the difference between the two values observable.
#
# Durations are compared loosely. Process::CLOCK_MONOTONIC in :millisecond truncates both
# endpoints, so a measured elapsed time is within a millisecond either side of the real
# one, and exact arithmetic on the values would be flaky.
# Defined outside the example group: constants assigned inside an RSpec block land on the
# example group class, which the anonymous Class.new bodies below cannot resolve.
SLEEP_SECONDS = 0.01
SLEEP_MS = 10
PERSIST_SLEEP_SECONDS = 0.02
PERSIST_SLEEP_MS = 20

# Stands in for Inferno::Repositories::Results and the Result entity it returns. Only the
# two things the patch touches are modelled: create returns something with an `id` and a
# writable `duration_ms`, and update writes to the stored row rather than the entity.
class FakeResultsRepo
  Result = Struct.new(:id, :duration_ms)

  attr_reader :rows

  def initialize
    @rows = {}
  end

  def create(name, duration_ms)
    id = "result-#{@rows.size}"
    @rows[id] = { name:, duration_ms: }
    Result.new(id, duration_ms)
  end

  def update(entity_id, params = {})
    @rows.fetch(entity_id).merge!(params)
  end
end

RSpec.describe InfernoPlatformTemplate::ResultDurationPatch do
  let(:runner_class) do
    Class.new do
      attr_reader :results_repo, :inserted

      def initialize
        @results_repo = FakeResultsRepo.new
        @inserted = []
      end

      def run_test(test, _scratch = {})
        sleep SLEEP_SECONDS
        result = persist_result(name: test)
        update_parent_result("#{test}-parent")
        result
      end

      def run_group(group, scratch = {})
        %w[child-a child-b].each { |child| run_test(child, scratch) }
        result = persist_result(name: group)
        update_parent_result("#{group}-parent")
        result
      end

      # Mirrors TestRunner#update_parent_result recursing up the tree, persisting an
      # ancestor's recomputed result at each level.
      def update_parent_result(parent, depth = 2)
        return if depth.zero?

        persist_result(name: parent)
        update_parent_result("#{parent}-up", depth - 1)
      end

      # Mirrors TestRunner#persist_result: the write cascades into the message, request and
      # header rows, which is the cost the second reading exists to capture.
      def persist_result(params)
        @inserted << params
        sleep PERSIST_SLEEP_SECONDS
        @results_repo.create(params[:name], params[:duration_ms])
      end
    end.tap { |klass| klass.prepend(described_class) }
  end

  let(:runner) { runner_class.new }

  # What ends up on the row, which is what the API serves.
  def durations_by_name
    runner.results_repo.rows.values.to_h { |row| [row[:name], row[:duration_ms]] }
  end

  # What the INSERT carried, before the corrective update.
  def inserted_durations_by_name
    runner.inserted.to_h { |params| [params[:name], params[:duration_ms]] }
  end

  describe 'a single test' do
    before { runner.run_test('test-1') }

    it 'attributes a measured duration to the test' do
      expect(durations_by_name['test-1']).to be_a(Integer)
      expect(durations_by_name['test-1']).to be >= SLEEP_MS - 1
    end

    it 'leaves parent roll-ups without a duration' do
      roll_ups = runner.results_repo.rows.values.reject { |row| row[:name] == 'test-1' }

      expect(roll_ups).to_not be_empty
      expect(roll_ups.map { |row| row[:duration_ms] }).to all(be_nil)
    end

    it 'issues no corrective update for a roll-up' do
      # A nil frame must skip the update as well as the insert, or the patch would write a
      # duration onto rows it deliberately declined to time.
      expect(runner.results_repo.rows.values.count { |row| row[:duration_ms] }).to eq(1)
    end
  end

  describe 'the cost of writing the result' do
    before { runner.run_test('test-1') }

    it 'counts persistence towards the recorded duration' do
      # The reason this matters: on a real AU Core run the write is 45% of the elapsed
      # time, and it scales with how many requests the test made, so omitting it
      # understates exactly the request-heavy tests a user is hunting for.
      expect(durations_by_name['test-1']).to be >= (SLEEP_MS + PERSIST_SLEEP_MS) - 1
    end

    it 'inserts the execution time and corrects it afterwards' do
      inserted = inserted_durations_by_name['test-1']

      expect(inserted).to be >= SLEEP_MS - 1
      expect(inserted).to be < SLEEP_MS + PERSIST_SLEEP_MS
      expect(durations_by_name['test-1']).to be > inserted
    end

    it 'corrects the row it just inserted rather than creating another' do
      expect(runner.results_repo.rows.count { |_id, row| row[:name] == 'test-1' }).to eq(1)
    end

    it 'leaves the returned entity agreeing with the row' do
      result = runner.run_test('test-2')

      expect(result.duration_ms).to eq(durations_by_name['test-2'])
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
