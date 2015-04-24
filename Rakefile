require_relative 'lib/version'

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
