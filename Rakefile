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

    # Local migrations are dev-only (performance monitoring schema); gated by
    # PERFORMANCE_MONITORING_ENABLED so prod's database schema is left untouched.
    if ENV['PERFORMANCE_MONITORING_ENABLED'] == 'true'
      require 'sequel'
      local_dir = File.join(__dir__, 'db', 'migrate')
      if File.directory?(local_dir) && !Dir.glob("#{local_dir}/*.rb").empty?
        db = Sequel.connect(
          adapter:  'postgres',
          host:     ENV.fetch('POSTGRES_HOST', 'localhost'),
          port:     ENV.fetch('POSTGRES_PORT', '5432').to_i,
          database: ENV.fetch('POSTGRES_DB', 'inferno'),
          user:     ENV.fetch('POSTGRES_USER', 'postgres'),
          password: ENV.fetch('POSTGRES_PASSWORD', '')
        )
        Sequel::Migrator.run(db, local_dir, table: :local_schema_migrations)
        db.disconnect
      end
    end
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

  desc 'Generate the static platform web site as local'
  task :generate_local do
    generate_static(["web/_config.yml", "web/_config.local.yml"])
  end

  desc 'Generate and serve the static web platform pages'
  task serve: [:generate] do

    sh "jekyll serve --skip-initial-build --no-watch"

  end

  desc 'Generate and serve the static web platform pages as dev'
  task serve_dev: [:generate_dev] do

    sh "jekyll serve --skip-initial-build --no-watch"

  end

  desc 'Generate and serve the static web platform pages as production'
  task serve_prod: [:generate_prod] do

    sh "jekyll serve --skip-initial-build --no-watch"

  end

  desc 'Generate and serve the static web platform pages as local'
  task serve_local: [:generate_local] do

    sh "jekyll serve --skip-initial-build --no-watch"

  end
end
