# frozen_string_literal: true

# Benchmarks the ReplayOptimizedPostgresPersistor with a replay-shaped workload: per aggregate a record is
# created, updated a number of times and read back, after which all records are committed.
#
# Usage: ruby benchmarks/replay_persistor.rb [lib directory] [number of aggregates]
#
# Set PROFILE to a file name to write a stackprof CPU profile of the in-memory part to that file.
#
# Needs a PostgreSQL server (PGHOST, PGPORT, PGUSER, PGPASSWORD) where the user can create databases.

require 'active_record'
require 'bigdecimal'
require 'securerandom'

lib = File.expand_path(ARGV[0] || File.join(__dir__, '..', 'lib'))
require File.join(lib, 'sequent/core/persistors/replay_optimized_postgres_persistor')
# Older versions of the persistor use Sequent::ApplicationRecord, which is not loaded here.
Sequent.const_set(:ApplicationRecord, ActiveRecord::Base) unless defined?(Sequent::ApplicationRecord)

AGGREGATES = Integer(ARGV[1] || 50_000)
UPDATES_PER_AGGREGATE = 5
RUNS = 3

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
    tags varchar[],
    payload jsonb,
    created_at timestamp NOT NULL,
    updated_at timestamp NOT NULL
  )
SQL

class BenchmarkRecord < ActiveRecord::Base; end
Event = Struct.new(:aggregate_id, :sequence_number, :created_at)

def replay(persistor, aggregate_ids, created_at)
  aggregate_ids.each do |aggregate_id|
    persistor.create_record(
      BenchmarkRecord,
      aggregate_id:,
      organization_id: aggregate_id,
      sequence_number: 1,
      name: 'name',
      description: 'a description',
      amount: BigDecimal('1.25'),
      book_date: Date.new(2026, 1, 1),
      active: true,
      tags: %w[a b],
      payload: {'k' => 1},
      created_at:,
    )
    UPDATES_PER_AGGREGATE.times do |i|
      persistor.update_all_records(
        BenchmarkRecord,
        {aggregate_id:},
        {name: "name #{i}", amount: BigDecimal(i), active: i.even?, sequence_number: i + 2},
      )
    end
    event = Event.new(aggregate_id, UPDATES_PER_AGGREGATE + 2, created_at)
    persistor.update_record(BenchmarkRecord, event) { |record| record.description = 'updated' }
    persistor.get_record!(BenchmarkRecord, aggregate_id:)
  end
end

clock = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
aggregate_ids = Array.new(AGGREGATES) { SecureRandom.uuid }
created_at = Time.now

results = Array.new(RUNS) do
  BenchmarkRecord.connection.execute('TRUNCATE benchmark_records')
  persistor = Sequent::Core::Persistors::ReplayOptimizedPostgresPersistor.new
  GC.start

  allocations = GC.stat(:total_allocated_objects)
  gc_time = GC.stat(:time)
  started = clock.call
  if ENV['PROFILE']
    require 'stackprof'
    StackProf.run(mode: :cpu, interval: 100, out: ENV.fetch('PROFILE')) { replay(persistor, aggregate_ids, created_at) }
  else
    replay(persistor, aggregate_ids, created_at)
  end
  replayed = clock.call
  allocations = GC.stat(:total_allocated_objects) - allocations
  gc_time = GC.stat(:time) - gc_time
  persistor.commit
  committed = clock.call

  fail 'not all records committed' unless BenchmarkRecord.count == AGGREGATES

  {in_memory: replayed - started, gc: gc_time / 1000.0, commit: committed - replayed, allocations:}
end

best = ->(key) { results.map { |r| r[key] }.min }
operations = AGGREGATES * (UPDATES_PER_AGGREGATE + 3)
puts "lib: #{lib}"
puts format(
  '%d aggregates, %d operations: in memory %.0f ms (%.2f µs/operation, %.1f allocations/operation, ' \
  '%.0f ms GC), commit %.0f ms, total %.0f ms',
  AGGREGATES,
  operations,
  best.call(:in_memory) * 1000,
  best.call(:in_memory) / operations * 1e6,
  best.call(:allocations).to_f / operations,
  best.call(:gc) * 1000,
  best.call(:commit) * 1000,
  (best.call(:in_memory) + best.call(:commit)) * 1000,
)
