# frozen_string_literal: true

source "https://rubygems.org"

ruby '3.3.6'

gem 'inferno_core', '~> 0.6.1'
gem 'pg'

# This loads the test kit suites
# These are published on Ruby Gems, but you can
# also point to git repos, or with some extra
# Docker configuration relative directories

gem 'au_core_test_kit', '~> 0.0.17'
gem 'au_ips_inferno', git: 'https://github.com/beda-software/au-ips-inferno', ref: '507ab792ec0a639d7e28e7389dcc51a4fc135cb0'
gem 'validation_test_kit', git: 'https://github.com/beda-software/validation-test-kit'
gem 'ips_test_kit', '~> 0.10.2'
gem 'ipa_test_kit', '~> 0.4.1'

gem 'sidekiq-cron'

group :development, :test do
  gem 'jekyll'
  gem 'database_cleaner-sequel', '~> 1.8'
  gem 'factory_bot', '~> 6.1'
  gem 'rspec', '~> 3.10'
  gem 'webmock', '~> 3.11'
end
