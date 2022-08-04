# frozen_string_literal: true

require_relative 'lib/version'
require_relative 'lib/sequent/application_record'
require_relative 'spec/database'

begin
  require 'rspec/core/rake_task'
  RSpec::Core::RakeTask.new(:spec)
rescue LoadError
  # ignore
end

require 'sequent'
require 'sequent/rake/migration_tasks'

Sequent::Rake::MigrationTasks.new.register_tasks!
Sequent.configuration.database_config_directory = 'tmp'

test_config = File.join(Sequent.configuration.database_config_directory, 'database.yml')
if Sequent.configuration.enable_multiple_database_support
  db_config = {}
  db_config[Sequent.configuration.primary_database_key.to_s] =
    Database.test_config[Sequent.configuration.primary_database_key.to_s].to_h
  db_config = db_config.to_h
  File.write(test_config, {'test' => db_config}.to_yaml)
else
  File.write(test_config, {'test' => Database.test_config.to_h}.to_yaml)
end

task 'sequent:migrate:init' => [:db_connect]

task 'db_connect' do
  Sequent::Support::Database.connect!(ENV['RACK_ENV'])
end

Bundler::GemHelper.install_tasks
