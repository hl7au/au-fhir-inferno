require 'inferno'
require_relative 'lib/inferno_platform_template/patches'

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

Inferno::Application.finalize!

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
