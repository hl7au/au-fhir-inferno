# frozen_string_literal: true

source "https://rubygems.org"

ruby '3.3.6'

gem 'inferno_core', '~> 1.0.6'
gem 'pg'

# This loads the test kit suites
# These are published on Ruby Gems, but you can
# also point to git repos, or with some extra
# Docker configuration relative directories

gem 'au_core_test_kit', git: 'https://github.com/hl7au/au-fhir-core-inferno', ref: '1446b9bf9016cbcf27871175ea69dd32c698c940'
# gem 'au_core_test_kit', '~> 1.4.0'
gem 'au_ps_inferno', git: 'https://github.com/hl7au/au-ps-inferno', ref: 'b1fc6fb778e184f441411e949e18f3177bda2efc'
gem 'validation_test_kit', git: 'https://github.com/beda-software/validation-test-kit'
gem 'inferno_suite_generator', github: 'hl7au/inferno_suite_generator', ref: 'b7d35902727343e898cd8d03dff600823b15384c'


gem 'sinatra'
gem 'sidekiq-cron'

# OpenTelemetry — worker emits spans to Alloy → Tempo
gem 'opentelemetry-sdk'
gem 'opentelemetry-exporter-otlp'
gem 'opentelemetry-instrumentation-faraday'
gem 'opentelemetry-instrumentation-net_http'
gem 'opentelemetry-instrumentation-sidekiq'

group :development, :test do
  gem 'jekyll'
  gem 'database_cleaner-sequel', '~> 1.8'
  gem 'factory_bot', '~> 6.1'
  gem 'rspec', '~> 3.10'
  gem 'webmock', '~> 3.11'
end
