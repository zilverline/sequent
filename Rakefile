require_relative 'lib/version'

task :build do
  `gem build sequent.gemspec`
end

task :release => :build do
  `git tag v#{Sequent::VERSION}`
  `git push --tags`
  `gem push sequent-#{Sequent::VERSION}`
end
