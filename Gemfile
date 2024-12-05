# frozen_string_literal: true

source "https://rubygems.org"

ruby '3.1.2'

gem 'inferno_core', '~> 0.4.44'
gem 'pg'

# This loads the test kit suites
# These are published on Ruby Gems, but you can
# also point to git repos, or with some extra
# Docker configuration relative directories

gem 'au_core_test_kit', git: 'https://github.com/hl7au/au-fhir-core-inferno', ref: 'bb8de66a310a6dcb800b71e9da83a2a6221346c3'
gem 'au_ips_inferno', git: 'https://github.com/beda-software/au-ips-inferno', ref: '7ce238858e07a8a46d934d2b46423d757cd53446'
gem 'validation_test_kit', git: 'https://github.com/beda-software/validation-test-kit'
gem 'ips_test_kit', git: 'https://github.com/beda-software/ips-test-kit', ref: 'c84ae59395c36422364cdf733b4e24f5b64a5670'
gem 'ipa_test_kit', git: 'https://github.com/inferno-framework/ipa-test-kit'

gem 'sidekiq-cron'

group :development, :test do
  gem 'jekyll'
  gem 'database_cleaner-sequel', '~> 1.8'
  gem 'factory_bot', '~> 6.1'
  gem 'rspec', '~> 3.10'
  gem 'webmock', '~> 3.11'
end
