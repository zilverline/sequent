require 'bundler/setup'
Bundler.setup

require 'rspec/collection_matchers'
require_relative '../lib/sequent/sequent'
require 'simplecov'

require_relative 'database'
Database.establish_connection
ActiveRecord::Base.connection.execute("TRUNCATE command_records, stream_records CASCADE")

RSpec.configure do |c|
  c.before do
    Sequent::Configuration.reset
  end
end
