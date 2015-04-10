require 'bundler/setup'
Bundler.setup

require 'rspec/collection_matchers'
require_relative '../lib/sequent/sequent'

require_relative 'database'
Database.establish_connection

ActiveRecord::Base.connection.execute("TRUNCATE command_records, stream_records CASCADE")
