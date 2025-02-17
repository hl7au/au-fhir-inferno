require 'rspec/core/rake_task'
require 'jekyll'
RSpec::Core::RakeTask.new(:spec)
task default: :spec

def generate_static(jekyll_config)
  require 'dotenv'
  Dotenv.load(File.join(Dir.pwd, '.env'))

  config = Jekyll.configuration({
    core_base_path: ENV['BASE_PATH'] ? "/#{ENV['BASE_PATH']}/" : '/',
    source: 'web',
    config: jekyll_config
  })

  site = Jekyll::Site.new(config)
  Jekyll::Commands::Build.build(site, config)
end

namespace :db do
  desc 'Apply changes to the database'
  task :migrate do
    require 'inferno/config/application'
    require 'inferno/utils/migration'
    Inferno::Utils::Migration.new.run
  end
end

namespace :web do
  desc 'Generate the static platform web site'
  task :generate do
    generate_static(["web/_config.yml", "web/_config.local.yml"])
  end

  desc 'Generate the static platform web site as prod'
  task :generate_prod do
    generate_static(["web/_config.yml", "web/_config.prod.yml"])
  end

  desc 'Generate the static platform web site as dev'
  task :generate_dev do
    generate_static(["web/_config.yml", "web/_config.dev.yml"])
  end

  desc 'Generate and serve the static web platform pages'
  task serve: [:generate] do

    sh "jekyll serve --skip-initial-build --no-watch"

  end

  desc 'Generate and serve the static web platform pages as production'
  task serve_prod: [:generate_prod] do

    sh "jekyll serve --skip-initial-build --no-watch"

  end
end
