# frozen_string_literal: true

source "https://rubygems.org"

gem 'pg'

# This loads the test kit suites
# These are published on Ruby Gems, but you can
# also point to git repos, or with some extra
# Docker configuration relative directories

gem 'us_core_test_kit', '0.6.5'
gem 'ipa_test_kit', '0.3.4'
gem 'au_core_test_kit', git: 'https://github.com/hl7au/au-fhir-core-inferno'
gem 'au_ips_inferno', git: 'https://github.com/beda-software/au-ips-inferno'
gem 'validation_test_kit', git: 'https://github.com/beda-software/validation-test-kit'

gem 'sidekiq-cron'

group :development, :test do
  gem 'jekyll'
  gem 'database_cleaner-sequel', '~> 1.8'
  gem 'factory_bot', '~> 6.1'
  gem 'rspec', '~> 3.10'
  gem 'webmock', '~> 3.11'
end
