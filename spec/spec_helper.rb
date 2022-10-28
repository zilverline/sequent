# frozen_string_literal: true

require 'bundler/setup'
Bundler.setup

ENV['SEQUENT_ENV'] ||= 'test'

require 'rspec/collection_matchers'
require 'timecop'
require_relative '../lib/sequent'
require_relative '../lib/sequent/generator'
require_relative './lib/sequent/fixtures/fixtures'
require './lib/sequent/test/database_helpers'
require 'simplecov'
SimpleCov.start if ENV['COVERAGE']

require_relative 'database'

Sequent.configuration.database_config_directory = 'tmp'
Database.write_database_yml_for_test(env: ENV['SEQUENT_ENV'])
Sequent::Test::DatabaseHelpers.maintain_test_database_schema(env: ENV['SEQUENT_ENV'])

RSpec.configure do |c|
  c.before do
    Database.establish_connection
    Sequent::ApplicationRecord.connection.execute('TRUNCATE command_records, stream_records CASCADE')
    Sequent::Configuration.reset
    Sequent.configuration.database_config_directory = 'tmp'
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
          events,
        ],
      ],
    )
  end
end

RSpec::Matchers.define :have_schema do |expected|
  schemas = []
  match do |connection|
    schemas = connection.execute('SELECT schema_name FROM information_schema.schemata').flat_map(&:values)
    expect(schemas).to include(expected)
  end

  failure_message do |_actual|
    %(expected database schemas:\n  #{schemas.join("\n  ")}\nto contain:\n  #{expected})
  end
end

RSpec::Matchers.define :have_view_schema_table do |expected|
  tables = []
  match do |connection|
    tables = connection
      .execute(<<~SQL.chomp).flat_map(&:values)
        SELECT table_name FROM information_schema.tables where table_schema = '#{Sequent.configuration.view_schema_name}'
      SQL
    expect(tables).to include(expected)
  end

  failure_message do |_actual|
    %(expected view schema tables:\n  #{tables.join("\n  ")}\nto contain:\n  #{expected})
  end
end

RSpec::Matchers.define :have_view_schema_index do |expected|
  index_names = []
  table_name = expected.split('.').first

  match do |connection|
    index_names = connection
      .execute("SELECT tablename || '.' || indexname FROM pg_indexes where tablename = '#{table_name}'")
      .flat_map(&:values)
    expect(index_names).to include(expected)
  end

  failure_message do |_actual|
    %(expected indexes for table #{table_name}:\n  #{index_names.join("\n  ")}\nto contain:\n  #{expected})
  end
end

RSpec::Matchers.define :have_column do |expected|
  match do |actual|
    actual.reset_column_information
    expect(actual.column_names).to include(expected)
  end

  failure_message do |actual|
    %(expected table #{actual.table_name} to have column '#{expected}')
  end
end
