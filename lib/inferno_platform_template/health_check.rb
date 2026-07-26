# Liveness and readiness endpoints for the inferno-app container.
#
# inferno_core exposes no health endpoint, and the only cheap route it does offer
# (/suites/api/version) is a static lambda that never touches the database. That
# distinction matters: the failure mode actually seen in preview environments is the
# Postgres pod being rescheduled while inferno-app keeps running, after which every
# pooled connection is dead and every request 500s with PG::ConnectionBad. The process
# is alive, so a liveness-only check would keep it in service indefinitely.
#
#   /healthz/live  - process is up and Rack is responding. No dependencies, so a slow
#                    or absent database can never cause a restart loop.
#   /healthz/ready - the app can actually serve traffic: a real round trip to the
#                    database. Fails the pod out of the Service endpoints while the
#                    database is unreachable, and (paired with the liveness probe) lets
#                    Kubernetes recycle a pod whose connection pool is permanently dead.
#
# Implemented as middleware rather than a mounted app so it can be installed ahead of
# Inferno's RequestLogger and short-circuit there: probes fire every few seconds forever,
# and routing them through the normal stack would add thousands of access-log lines a day.
#
# Kept adapter-agnostic ('SELECT 1' through Sequel) so it works on the Postgres
# deployments and the sqlite development/test configs alike. The probe's own
# timeoutSeconds bounds a hung check, so no statement_timeout is set here.
module InfernoPlatformTemplate
  class HealthCheck
    PREFIX = '/healthz'.freeze
    JSON_HEADERS = { 'Content-Type' => 'application/json' }.freeze

    def initialize(app)
      @app = app
    end

    def call(env)
      path = env['PATH_INFO'].to_s
      return @app.call(env) unless path.start_with?(PREFIX)

      case path.delete_prefix(PREFIX).chomp('/')
      when '/live'
        json(200, status: 'ok')
      when '/ready'
        readiness
      else
        json(404, status: 'not_found')
      end
    end

    private

    def readiness
      Inferno::Application['db.connection'].fetch('SELECT 1').first
      json(200, status: 'ok', database: 'ok')
    rescue StandardError => e
      # Warn rather than error: a rescheduled database makes this fire every probe
      # interval, and the pod's Ready condition already carries the signal.
      Inferno::Application['logger']&.warn("readiness check failed: #{e.class}: #{e.message}")
      json(503, status: 'unavailable', database: e.class.to_s)
    end

    def json(status, **body)
      [status, JSON_HEADERS, [body.to_json]]
    end
  end
end
