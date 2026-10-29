# frozen_string_literal: true

# Compares the BufferedPersistor with the ActiveRecordPersistor for projectors that handle an event per changed
# attribute. Each batch of events (like the events of a single command) is handled in its own transaction.
#
# Usage: ruby benchmarks/buffered_persistor.rb [number of batches]
#
# Needs a PostgreSQL server (PGHOST, PGPORT, PGUSER, PGPASSWORD) where the user can create databases.

require 'active_record'
require 'bigdecimal'
require 'securerandom'

lib = File.expand_path(File.join(__dir__, '..', 'lib'))
require File.join(lib, 'sequent/core/persistors/active_record_persistor')
require File.join(lib, 'sequent/core/persistors/buffered_persistor')

BATCHES = Integer(ARGV[0] || 2_000)
UPDATES_PER_BATCH = 10

DATABASE = "sequent_benchmark_#{Process.pid}".freeze
CONFIG = {
  adapter: 'postgresql',
  host: ENV.fetch('PGHOST', 'localhost'),
  port: ENV.fetch('PGPORT', 5432),
  username: ENV.fetch('PGUSER', 'sequent'),
  password: ENV.fetch('PGPASSWORD', 'sequent'),
}.freeze

ActiveRecord::Base.establish_connection(**CONFIG, database: 'postgres')
ActiveRecord::Base.connection.execute("CREATE DATABASE #{DATABASE}")
at_exit do
  ActiveRecord::Base.establish_connection(**CONFIG, database: 'postgres')
  ActiveRecord::Base.connection.execute("DROP DATABASE IF EXISTS #{DATABASE}")
end
ActiveRecord::Base.establish_connection(**CONFIG, database: DATABASE)
ActiveRecord::Base.connection.execute(<<~SQL)
  CREATE TABLE benchmark_records (
    id bigserial PRIMARY KEY,
    aggregate_id uuid NOT NULL,
    organization_id uuid NOT NULL,
    sequence_number integer NOT NULL,
    name varchar,
    description text,
    amount numeric(12,2),
    book_date date,
    active boolean,
    created_at timestamp NOT NULL,
    updated_at timestamp NOT NULL
  )
SQL
ActiveRecord::Base.connection.execute('CREATE INDEX ON benchmark_records (aggregate_id)')

class BenchmarkRecord < ActiveRecord::Base; end

def create(persistor, aggregate_id)
  persistor.create_record(
    BenchmarkRecord,
    aggregate_id:,
    organization_id: aggregate_id,
    sequence_number: 1,
    name: 'name',
    created_at: Time.now,
    updated_at: Time.now,
  )
end

def update_attributes(persistor, aggregate_id)
  UPDATES_PER_BATCH.times do |i|
    attribute = [
      {name: "name #{i}"},
      {description: "description #{i}"},
      {amount: BigDecimal(i)},
      {book_date: Date.new(2026, 1, 1) + i},
      {active: i.even?},
    ][i % 5]
    persistor.update_all_records(BenchmarkRecord, {aggregate_id:}, attribute.merge(sequence_number: i + 2))
  end
end

def run(persistor, aggregate_ids, create:)
  statements = 0
  callback = ->(*, payload) { statements += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name]) }
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
    aggregate_ids.each do |aggregate_id|
      ActiveRecord::Base.transaction do
        create(persistor, aggregate_id) if create
        update_attributes(persistor, aggregate_id)
        persistor.flush if persistor.respond_to?(:flush)
      end
    end
  end
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  [elapsed, statements]
end

persistors = {
  'ActiveRecordPersistor' => Sequent::Core::Persistors::ActiveRecordPersistor.new,
  'BufferedPersistor' => Sequent::Core::Persistors::BufferedPersistor.new,
}

# Warm up
persistors.each_value { |persistor| run(persistor, Array.new(50) { SecureRandom.uuid }, create: true) }

results = {}
puts "#{BATCHES} batches of #{UPDATES_PER_BATCH} attribute updates"
{'create and update' => true, 'update existing' => false}.each do |scenario, create|
  puts "#{scenario}:"
  persistors.each do |name, persistor|
    aggregate_ids = Array.new(BATCHES) { SecureRandom.uuid }
    run(Sequent::Core::Persistors::ActiveRecordPersistor.new, aggregate_ids, create: true) unless create
    elapsed, statements = run(persistor, aggregate_ids, create:)
    results[[scenario, name]] = elapsed
    puts format(
      '  %-22s %8.0f ms  %6.3f ms/batch  %5.1f statements/batch',
      name,
      elapsed * 1000,
      elapsed / BATCHES * 1000,
      statements.to_f / BATCHES,
    )
  end
end
