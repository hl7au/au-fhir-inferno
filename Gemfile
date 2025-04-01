# frozen_string_literal: true

source "https://rubygems.org"

ruby '3.3.6'

gem 'inferno_core', '~> 0.6.2'
gem 'pg'

# This loads the test kit suites
# These are published on Ruby Gems, but you can
# also point to git repos, or with some extra
# Docker configuration relative directories

# gem 'au_core_test_kit', '~> 0.0.18'
gem 'au_core_test_kit', git: 'https://github.com/hl7au/au-fhir-core-inferno', ref: '86e6dee2fff2a7071c1370e0e731fccc4757a6cd'
gem 'au_ps_inferno', git: 'https://github.com/hl7au/au-ps-inferno', ref: '5205f58a9a48a84b08113af3095ba417f3211e11'
gem 'validation_test_kit', git: 'https://github.com/beda-software/validation-test-kit'

gem 'sidekiq-cron'

group :development, :test do
  gem 'jekyll'
  gem 'database_cleaner-sequel', '~> 1.8'
  gem 'factory_bot', '~> 6.1'
  gem 'rspec', '~> 3.10'
  gem 'webmock', '~> 3.11'
end
