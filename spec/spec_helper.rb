require 'bundler/setup'
Bundler.setup

require 'rspec/collection_matchers'
require_relative '../lib/sequent/sequent'

RSpec.configure do |c|
  c.before do
    Sequent::Configuration.reset
  end
end
