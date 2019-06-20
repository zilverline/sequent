require_relative 'lib/version'
require_relative 'lib/sequent/application_record'
require_relative 'spec/database'

begin
  require 'rspec/core/rake_task'
  RSpec::Core::RakeTask.new(:spec)
rescue LoadError
end

task 'db:create' do
  Database.establish_connection
  load('db/sequent_schema.rb')
end

Bundler::GemHelper.install_tasks
