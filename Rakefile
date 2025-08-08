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

ActiveRecord::Base.configurations = YAML.load_file('db/database.yml', aliases: true)
ActiveRecord::Tasks::DatabaseTasks.env = Sequent.env
ActiveRecord::Tasks::DatabaseTasks.db_dir = 'db'
Sequent::Rake::MigrationTasks.new.register_tasks!

Bundler::GemHelper.install_tasks
