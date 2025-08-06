# frozen_string_literal: true

require 'bundler/setup'
Bundler.setup

ENV['SEQUENT_ENV'] ||= 'test'

require 'rspec/collection_matchers'
require 'timecop'
require_relative '../lib/sequent'
require_relative '../lib/sequent/generator'
require_relative '../lib/sequent/test'
require_relative 'lib/sequent/fixtures/fixtures'
require './lib/sequent/test/database_helpers'
require 'simplecov'
SimpleCov.start if ENV['COVERAGE']

require_relative 'database'

ActiveRecord::Tasks::DatabaseTasks.db_dir = 'db'

RSpec.configure do |c|
  c.before do
    env = Sequent.env

    Timecop.return
    Sequent::Configuration.reset

    ActiveRecord::Base.configurations = {env => Database.test_config}
    ActiveRecord::Base.establish_connection(env.to_sym)
    Sequent::Test::DatabaseHelpers.maintain_test_database_schema(env:)
    ActiveRecord::Base.connection.execute('TRUNCATE commands, aggregates, saved_event_records CASCADE')
  end

  def exec_sql(sql)
    Sequent::ApplicationRecord.connection.execute(sql)
  end

  def insert_events(aggregate_type, events, events_partition_key: '')
    streams_with_events = events.group_by(&:aggregate_id).map do |aggregate_id, aggregate_events|
      [
        Sequent::Core::EventStream.new(aggregate_type:, aggregate_id:, events_partition_key:),
        aggregate_events,
      ]
    end
    Sequent.configuration.event_store.commit_events(
      Sequent::Core::Command.new(events.first.attributes),
      streams_with_events,
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
