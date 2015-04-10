task 'db:create' do
  require_relative 'spec/spec_helper'
  load('db/schema.rb')
end

begin
  require 'rspec/core/rake_task'
  RSpec::Core::RakeTask.new(:spec)
rescue LoadError
end
