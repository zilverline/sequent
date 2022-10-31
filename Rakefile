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

Database.write_database_yml_for_test(env: 'test')

task 'sequent:migrate:init' => [:db_connect]

task 'db_connect' do
  Sequent::Support::Database.connect!(ENV['SEQUENT_ENV'])
end

Bundler::GemHelper.install_tasks
