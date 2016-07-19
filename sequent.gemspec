require_relative 'lib/version'

Gem::Specification.new do |s|
  s.platform    = Gem::Platform::RUBY
  s.name        = 'sequent'
  s.version     = Sequent::VERSION
  s.summary     = "Event sourcing framework for Ruby"
  s.description = "Sequent is a CQRS and event sourcing framework for Ruby."
  s.authors     = ["Lars Vonk", "Bob Forma", "Erik Rozendaal"]
  s.email       = ["lars.vonk@gmail.com", "bforma@zilverline.com", "erozendaal@zilverline.com"]
  s.files       = Dir["lib/**/*", "db/**/*"]
  s.homepage    =
    'https://github.com/zilverline/sequent'
  s.license       = 'MIT'

  s.add_dependency              'activerecord', '~> 4.0'
  s.add_dependency              'activemodel', '~> 4.0'
  s.add_dependency              'pg', '~> 0.18'
  s.add_dependency              'postgresql_cursor', '~> 0.6'
  s.add_dependency              'oj', '~> 2.10'
  s.add_dependency              'thread_safe', '~> 0.3.5'
  s.add_dependency              'google_hash', '~> 0.9.0'
  s.add_development_dependency  'rspec', '~> 3.2'
  s.add_development_dependency  'rspec-mocks', '~> 3.2'
  s.add_development_dependency  'rspec-collection_matchers', '~> 1.1'
  s.add_development_dependency  'rake', '~> 10.4'
  s.add_development_dependency  'pry', '~> 0.10'
end
