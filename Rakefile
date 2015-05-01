require_relative 'lib/version'
require_relative 'spec/database'

begin
  require 'rspec/core/rake_task'
  RSpec::Core::RakeTask.new(:spec)
rescue LoadError
end

task 'db:create' do
  Database.establish_connection
  load('db/schema.rb')
end

desc 'build a release'
task :build do
  `gem build sequent.gemspec`
end

desc 'tag and push release to git and rubygems'
task :release => :build do
  `git tag v#{Sequent::VERSION}`
  `git push --tags`
  `gem push sequent-#{Sequent::VERSION}.gem`
end
