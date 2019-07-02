require 'bundler/setup'
Bundler.setup

ENV['RACK_ENV'] ||= 'test'

require 'rspec/collection_matchers'
require_relative '../lib/sequent'
require_relative './lib/sequent/fixtures/fixtures'
require 'simplecov'
SimpleCov.start if ENV["COVERAGE"]

require_relative 'database'
Database.establish_connection
Sequent::ApplicationRecord.connection.execute("TRUNCATE command_records, stream_records CASCADE")

RSpec.configure do |c|
  c.before do
    Sequent::Configuration.reset
  end

  def exec_sql(sql)
    Sequent::ApplicationRecord.connection.execute(sql)
  end

  def insert_events(aggregate_type, events)
    Sequent.configuration.event_store.commit_events(
      Sequent::Core::CommandRecord.new,
      [
        [
          Sequent::Core::EventStream.new(aggregate_type: aggregate_type, aggregate_id: events.first.aggregate_id),
          events
        ]
      ]
    )
  end
end

RSpec::Matchers.define :have_schema do |expected|
  schemas = []
  match do |connection|
    schemas = connection.execute('SELECT schema_name FROM information_schema.schemata').flat_map { |r| r.values }
    expect(schemas).to include(expected)
  end

  failure_message do |_actual|
    %Q{expected database schemas:\n  #{schemas.join("\n  ")}\nto contain:\n  #{expected}}
  end
end

RSpec::Matchers.define :have_view_schema_table do |expected|
  tables = []
  match do |connection|
    tables = connection.execute("SELECT table_name FROM information_schema.tables where table_schema = '#{Sequent.configuration.view_schema_name}'").flat_map { |r| r.values }
    expect(tables).to include(expected)
  end

  failure_message do |_actual|
    %Q{expected view schema tables:\n  #{tables.join("\n  ")}\nto contain:\n  #{expected}}
  end
end

RSpec::Matchers.define :have_column do |expected|
  match do |record_class|
    record_class.reset_column_information
    expect(record_class.column_names).to include(expected)
  end

  # failure_message do |_actual|
  #   %Q{expected view schema tables:\n  #{tables.join("\n  ")}\nto contain:\n  #{expected}}
  # end
end
