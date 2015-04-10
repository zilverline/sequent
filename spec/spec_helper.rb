require 'bundler/setup'
Bundler.setup

require 'rspec/collection_matchers'
require_relative '../lib/sequent/sequent'

ActiveRecord::Base.establish_connection(
  :adapter  => "postgresql",
  :host     => "localhost",
  :username => "sequent",
  :password => "",
  :database => "sequent_spec_db"
)

ActiveRecord::Base.connection.execute("TRUNCATE command_records, stream_records CASCADE")
