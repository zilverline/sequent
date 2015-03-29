require_relative 'lib/version'

Gem::Specification.new do |s|
  s.platform    = Gem::Platform::RUBY
  s.name        = 'sequent'
  s.version     = Sequent::VERSION
  s.date        = '2014-03-15'
  s.summary     = "Event sourcing framework for Ruby"
  s.description = "Sequent is an event sourcing framework for Ruby. It supports multitentant Sinatra backed applications by default."
  s.authors     = ["Lars Vonk", "Bob Forma", "Erik Rozendaal"]
  s.email       = ["lars.vonk@gmail.com", "bforma@zilverline.com", "erozendaal@zilverline.com"]
  s.files       = ["lib/sequent/sequent.rb"]
  s.homepage    =
    'https://github.com/zilverline/sequent'
  s.license       = 'MIT'

  s.add_dependency              'activerecord', '~> 4.0.10'
  s.add_dependency              'activemodel', '~> 4.0.10'
  s.add_dependency              'pg', '~> 0.18.1'
  s.add_dependency              'oj', '~> 2.10.3'
  s.add_dependency              'rack_csrf', '~> 2.5.0'
  s.add_dependency              'sinatra', '~> 1.4.5'
  s.add_development_dependency  'rspec', '~> 3.2.0'
  s.add_development_dependency  'rspec-mocks', '~> 3.2.0'
  s.add_development_dependency  'rspec-collection_matchers', '~> 1.1.2'
end
