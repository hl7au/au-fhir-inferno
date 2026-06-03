require 'inferno'
require_relative 'lib/inferno_platform_template/request_timing'
require_relative 'lib/performance_app'

use Rack::Static,
    urls: Inferno::Utils::StaticAssets.static_assets_map,
    root: Inferno::Utils::StaticAssets.inferno_path

Inferno::Application.finalize!

use Inferno::Utils::Middleware::RequestLogger

run Rack::URLMap.new(
  '/api/performance' => InfernoPlatformTemplate::PerformanceApp.new,
  '/performance'     => InfernoPlatformTemplate::PerformanceApp.new,
  '/'                => Inferno::Web.app
)
