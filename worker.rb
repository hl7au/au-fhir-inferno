require 'inferno'
require 'sidekiq-cron'

require_relative 'lib/inferno_platform_template/delete_old_sessions'
require_relative 'lib/inferno_platform_template/patches'
require_relative 'lib/inferno_platform_template/request_timing'
require_relative 'lib/inferno_platform_template/validator_timing'

# Configure OpenTelemetry for inferno-worker spans.
# Env vars set by the Helm chart:
#   OTEL_SERVICE_NAME              = inferno-worker
#   OTEL_EXPORTER_OTLP_ENDPOINT   = http://k8s-monitoring-alloy-metrics.monitoring.svc:4318
#   OTEL_EXPORTER_OTLP_PROTOCOL   = http/protobuf
if ENV['OTEL_EXPORTER_OTLP_ENDPOINT']
  require 'opentelemetry/sdk'
  require 'opentelemetry/exporter/otlp'
  require 'opentelemetry/instrumentation/faraday'
  require 'opentelemetry/instrumentation/net/http'
  require 'opentelemetry/instrumentation/sidekiq'

  OpenTelemetry::SDK.configure do |c|
    c.use 'OpenTelemetry::Instrumentation::Faraday'
    c.use 'OpenTelemetry::Instrumentation::Net::HTTP'
    c.use 'OpenTelemetry::Instrumentation::Sidekiq'
  end
end

Inferno::Application.finalize!

InfernoPlatformTemplate::DeleteOldSessions.add_to_schedule
