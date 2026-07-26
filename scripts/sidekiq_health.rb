# Liveness/readiness check for the inferno-worker (Sidekiq) container.
#
# Sidekiq is not an HTTP server, so there is nothing for an httpGet probe to talk to and
# inferno-worker has historically run with no probe at all: a Sidekiq process that exits
# or wedges is never noticed and never restarted, and the pod keeps reporting Ready.
#
# Sidekiq's own process heartbeat is the authoritative liveness signal. Every Sidekiq
# process refreshes a Redis key every 5 seconds while its heartbeat thread is healthy, so
# "my hostname is in the ProcessSet" means this specific process is alive and pumping.
#
# Deliberate design point: an unreachable Redis exits 0 (healthy), not 1. This check can
# only prove a process is dead when Redis is reachable and says so; if Redis itself is
# down the check is *inconclusive*, and failing it would restart every worker in a
# restart loop for the duration of a Redis outage, turning a queue outage into a crash
# loop. Only a definite "Redis is up and has no fresh heartbeat for me" fails.
#
# Exit 0 = healthy or inconclusive, exit 1 = definitely unhealthy.

require 'sidekiq/api'

# Heartbeats refresh every 5s; allow several missed beats before calling it dead so a GC
# pause or a brief Redis blip cannot fail the probe.
STALE_AFTER_SECONDS = 60

begin
  Sidekiq.configure_client do |config|
    config.redis = { url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0') }
  end

  hostname = ENV.fetch('HOSTNAME', nil)
  if hostname.nil? || hostname.empty?
    warn 'sidekiq_health: HOSTNAME unset, cannot identify this process; treating as healthy'
    exit 0
  end

  process = Sidekiq::ProcessSet.new.find { |p| p['hostname'] == hostname }

  if process.nil?
    warn "sidekiq_health: no Sidekiq process registered for #{hostname}"
    exit 1
  end

  age = Time.now.to_i - process['beat'].to_i
  if age > STALE_AFTER_SECONDS
    warn "sidekiq_health: heartbeat for #{hostname} is #{age}s old (>#{STALE_AFTER_SECONDS}s)"
    exit 1
  end

  exit 0
rescue StandardError => e
  # Redis unreachable, auth failure, DNS, etc. Inconclusive: see the note above.
  warn "sidekiq_health: check inconclusive (#{e.class}: #{e.message}); treating as healthy"
  exit 0
end
