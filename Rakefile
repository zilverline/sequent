require_relative 'spec/database'

task 'db:create' do
  Database.establish_connection
  load('db/schema.rb')
end

begin
  require 'rspec/core/rake_task'
  RSpec::Core::RakeTask.new(:spec)
rescue LoadError
end
