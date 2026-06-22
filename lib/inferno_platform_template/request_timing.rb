require 'inferno'

# Captures wall-clock time for each outbound HTTP request made during test
# execution and persists it in the `duration_ms` column (added by local
# migration 001_add_duration_ms_to_requests.rb).
#
# The thread-local trick is needed because inferno_core serialises the entity
# (calls to_hash) *inside* store_request, before returning it.  We can't set
# duration_ms on the entity first without also patching to_hash to include it.
# The thread-local is set immediately after block.call returns and cleared in
# an ensure block so it never leaks across requests.

module InfernoPlatformTemplate
  # Patch Inferno::Entities::Request so that:
  #   1. duration_ms is readable/writable as an instance attribute.
  #   2. to_hash includes duration_ms when it is set (either via the
  #      thread-local during the initial save, or directly on a loaded entity).
  module RequestTimingAttributes
    def duration_ms
      @duration_ms
    end

    def duration_ms=(val)
      @duration_ms = val
    end

    def to_hash
      hash = super
      ms = @duration_ms || Thread.current[:inferno_request_duration_ms]
      ms ? hash.merge(duration_ms: ms.to_i) : hash
    end
  end

  # Patch Inferno::DSL::RequestStorage so that store_request measures the
  # elapsed milliseconds and makes them available to to_hash via a thread-local.
  module RequestStorageTimingPatch
    def store_request(direction, name: nil, tags: [], &block)
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
      timed_block = proc do
        result = block.call
        Thread.current[:inferno_request_duration_ms] =
          Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond) - t0
        result
      end
      request = super(direction, name: name, tags: tags, &timed_block)
      # Also set on the returned entity so in-memory callers can read it.
      request&.duration_ms = Thread.current[:inferno_request_duration_ms]
      request
    ensure
      Thread.current[:inferno_request_duration_ms] = nil
    end
  end
end

Inferno::Entities::Request.prepend(InfernoPlatformTemplate::RequestTimingAttributes)
Inferno::DSL::RequestStorage.prepend(InfernoPlatformTemplate::RequestStorageTimingPatch)
