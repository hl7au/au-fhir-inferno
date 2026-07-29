require 'inferno'
require_relative 'lib/inferno_platform_template/patches'
require_relative 'lib/inferno_platform_template/health_check'
require_relative 'lib/inferno_platform_template/database_pool'

# Per-runnable duration tracking (results.duration_ms) is dev-only while it is a
# prototype of an inferno-core change, gated by RESULT_DURATION_ENABLED. The web process
# needs it for the entity and serializer patches that expose duration_ms on
# /api/test_sessions/:id/results; the worker needs it to do the measuring (worker.rb).
require_relative 'lib/inferno_platform_template/result_duration' if ENV['RESULT_DURATION_ENABLED'] == 'true'

# Configure OpenTelemetry for inferno-app spans, mirroring worker.rb.
# Env vars set by the Helm chart:
#   OTEL_SERVICE_NAME            = inferno-app
#   OTEL_EXPORTER_OTLP_ENDPOINT  = http://k8s-monitoring-alloy-metrics.monitoring.svc:4318
#   OTEL_EXPORTER_OTLP_PROTOCOL  = http/protobuf
#
# The worker was instrumented first because test runs execute there, which left everything
# the web process does untraced. That is the larger blind spot: session creation serialises
# the entire suite tree and is the request that has actually timed out in production
# (au_core_v210_draft cost seconds of pure CPU before the fix in patches.rb), and it never
# appears in a trace because it is not part of a test run.
OTEL_ENABLED = !ENV['OTEL_EXPORTER_OTLP_ENDPOINT'].nil?
if OTEL_ENABLED
  require 'opentelemetry/sdk'
  require 'opentelemetry/exporter/otlp'
  require 'opentelemetry/instrumentation/faraday'
  require 'opentelemetry/instrumentation/net/http'
  require 'opentelemetry/instrumentation/rack'

  OpenTelemetry::SDK.configure do |c|
    c.use 'OpenTelemetry::Instrumentation::Faraday'
    c.use 'OpenTelemetry::Instrumentation::Net::HTTP'
    c.use 'OpenTelemetry::Instrumentation::Rack'
  end
end

# Outermost middleware: /healthz answers before static assets, the request logger and
# routing, so probes stay cheap and out of the access log. It also sits above the
# OpenTelemetry middleware below, so probe traffic never reaches the tracer.
use InfernoPlatformTemplate::HealthCheck

# Performance monitoring (request/validator timing + the /performance page) is dev-only,
# gated by PERFORMANCE_MONITORING_ENABLED. Kept off in prod so the timing middleware —
# which writes to columns created only by the dev-only local migration — is never loaded.
PERFORMANCE_MONITORING = ENV['PERFORMANCE_MONITORING_ENABLED'] == 'true'
if PERFORMANCE_MONITORING
  require_relative 'lib/inferno_platform_template/request_timing'
  require_relative 'lib/inferno_platform_template/validator_timing'
  require_relative 'lib/inferno_platform_template/performance_app'
end

use Rack::Static,
    urls: Inferno::Utils::StaticAssets.static_assets_map,
    root: Inferno::Utils::StaticAssets.inferno_path

# Below Rack::Static so asset requests, which the static middleware answers and never
# forwards, do not each cost a span. What remains is the dynamic traffic, the same scope
# the request logger covers.
#
# middleware_args is the instrumentation's own entry point rather than a hardcoded
# middleware constant: 0.31 splits the handler three ways by HTTP semantic-convention
# stability (stable / dup / old, selected by OTEL_SEMCONV_STABILITY_OPT_IN) and this
# resolves the right one. It has to run after SDK.configure, which is what loads the
# handler it returns.
use(*OpenTelemetry::Instrumentation::Rack::Instrumentation.instance.middleware_args) if OTEL_ENABLED

Inferno::Application.finalize!

InfernoPlatformTemplate::DatabasePool.configure!

use Inferno::Utils::Middleware::RequestLogger

if PERFORMANCE_MONITORING
  run Rack::URLMap.new(
    '/api/performance' => InfernoPlatformTemplate::PerformanceApp.new,
    '/performance'     => InfernoPlatformTemplate::PerformanceApp.new,
    '/'                => Inferno::Web.app
  )
else
  run Inferno::Web.app
end
