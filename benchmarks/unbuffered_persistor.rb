# frozen_string_literal: true

# Compares the ActiveRecordPersistor with persistors that keep records as structs (like the
# ReplayOptimizedPostgresPersistor) but write every change to the database right away, using different ways to
# generate and execute the statements:
#
# - active_record:  ActiveRecordPersistor, instantiating models and saving them.
# - unbuffered:     UnbufferedPersistor, structs written with insert_all!/update_all/delete_all and read with pluck.
# - sql_literals:   structs, own SQL with quoted values.
# - sql_binds:      structs, own SQL with binds, executed by ActiveRecord without preparing it.
# - sql_prepared:   structs, own SQL with binds, prepared by ActiveRecord.
# - pg_params:      structs, own SQL with binds, executed by the pg gem without preparing it.
# - pg_prepared:    structs, own SQL with binds, prepared by the pg gem.
#
# The workload is projector-shaped: per aggregate a record is created, updated using update_all_records a number of
# times, updated using update_record (read, change and write), read back, and every tenth record is deleted. The
# statements of 100 aggregates run in one transaction.
#
# Usage: ruby benchmarks/unbuffered_persistor.rb [number of aggregates] [variant...]
#
# Needs a PostgreSQL server (PGHOST, PGPORT, PGUSER, PGPASSWORD) where the user can create databases.

require 'active_record'
require 'bigdecimal'
require 'securerandom'

lib = File.expand_path(File.join(__dir__, '..', 'lib'))
require File.join(lib, 'sequent/core/persistors/active_record_persistor')
require File.join(lib, 'sequent/core/persistors/record_structs')
require File.join(lib, 'sequent/core/persistors/unbuffered_persistor')
Sequent.const_set(:ApplicationRecord, ActiveRecord::Base) unless defined?(Sequent::ApplicationRecord)

AGGREGATES = Integer(ARGV[0] || 5_000)
VARIANTS = ARGV[1..].presence&.map(&:to_sym)
UPDATES_PER_AGGREGATE = 5
AGGREGATES_PER_TRANSACTION = 100
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
  ActiveRecord::Base.connection_handler.clear_all_connections!
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
  );
  CREATE INDEX ON benchmark_records (aggregate_id);
SQL

class BenchmarkRecord < ActiveRecord::Base; end
Event = Struct.new(:aggregate_id, :sequence_number, :created_at)

# A sketch of an UnbufferedPersistor that generates its own SQL, using a statement strategy.
class StructPersistor
  RecordStructs = Sequent::Core::Persistors::RecordStructs

  def initialize(statements)
    @statements = statements
  end

  def create_record(record_class, values, &block)
    record = RecordStructs.create(record_class, values, &block)
    @statements.insert(record_class, record)
    record
  end

  def update_all_records(record_class, where_clause, updates)
    @statements.update(record_class, where_clause, updates)
  end

  def delete_all_records(record_class, where_clause)
    @statements.delete(record_class, where_clause)
  end

  def get_record!(record_class, where_clause)
    get_record(record_class, where_clause) or fail "#{record_class} #{where_clause} not found"
  end

  def get_record(record_class, where_clause)
    @statements.select_first(record_class, where_clause)
  end

  def update_record(record_class, event, where_clause = {aggregate_id: event.aggregate_id}, _options = {})
    record = get_record!(record_class, where_clause)
    before = record.to_h
    record.updated_at = event.created_at if record.respond_to?(:updated_at=)
    yield record if block_given?
    record.sequence_number = event.sequence_number if record.respond_to?(:sequence_number=)
    changes = record.to_h.reject { |column, value| before[column] == value }
    @statements.update(record_class, {id: record.id}, changes) unless changes.empty?
    record
  end

  def flush = nil
end

# Generates the SQL itself, and caches it per record class, statement kind and columns.
class SqlStatements
  def initialize
    @sql = {}
  end

  def insert(record_class, record)
    computed = StructPersistor::RecordStructs.record_class(record_class).computed_columns
    values = record.to_h.reject { |column, value| value.nil? && computed.include?(column) }
    sql = cached(:insert, record_class, values.keys) do
      "INSERT INTO #{table(record_class)} (#{column_list(values.keys)}) " \
        "VALUES (#{placeholders(values.size)}) RETURNING \"id\""
    end
    record.id = Integer(execute(sql, record_class, values, returning: true))
  end

  def update(record_class, where_clause, updates)
    sql = cached(:update, record_class, updates.keys, where_clause.keys) do
      sets = updates.keys.each_with_index.map { |column, i| "#{quote_column(column)} = #{placeholder(i + 1)}" }
      "UPDATE #{table(record_class)} SET #{sets.join(', ')} WHERE #{conditions(where_clause.keys, updates.size)}"
    end
    execute(sql, record_class, updates.merge(where_clause.transform_keys { |column| :"where_#{column}" }))
  end

  def delete(record_class, where_clause)
    sql = cached(:delete, record_class, where_clause.keys) do
      "DELETE FROM #{table(record_class)} WHERE #{conditions(where_clause.keys, 0)}"
    end
    execute(sql, record_class, where_clause)
  end

  def select_first(record_class, where_clause)
    columns = StructPersistor::RecordStructs.record_class(record_class)
    sql = cached(:select, record_class, where_clause.keys) do
      "SELECT #{column_list(columns.column_names)} FROM #{table(record_class)} " \
        "WHERE #{conditions(where_clause.keys, 0)} LIMIT 1"
    end
    row = select(sql, record_class, where_clause)
    row && columns.struct.new(
      *columns.column_names.each_with_index.map do |name, i|
        record_class.type_for_attribute(name).deserialize(row[i])
      end,
    )
  end

  private

  def cached(*key) = @sql[key] ||= yield

  def connection = ActiveRecord::Base.connection

  def table(record_class) = connection.quote_table_name(record_class.table_name)

  def quote_column(column) = connection.quote_column_name(column)

  def column_list(columns) = columns.map { |column| quote_column(column) }.join(', ')

  def placeholders(count) = (1..count).map { |i| placeholder(i) }.join(', ')

  def placeholder(index) = "$#{index}"

  def conditions(columns, offset)
    columns.each_with_index.map { |column, i| "#{quote_column(column)} = #{placeholder(offset + i + 1)}" }.join(' AND ')
  end

  # The column of a value, also for the values of a where clause, whose keys are prefixed with +where_+.
  def column_name(column) = column.to_s.delete_prefix('where_')

  def serialized(record_class, values)
    values.map { |column, value| record_class.type_for_attribute(column_name(column)).serialize(value) }
  end
end

# Inlines the values as quoted literals.
class SqlLiteralStatements < SqlStatements
  private

  def placeholder(index) = "\x00#{index}\x00"

  def inline(sql, record_class, values)
    literals = serialized(record_class, values).map { |value| connection.quote(value) }
    sql.gsub(/\x00(\d+)\x00/) { literals[Integer(::Regexp.last_match(1)) - 1] }
  end

  def execute(sql, record_class, values, returning: false)
    sql = inline(sql, record_class, values)
    returning ? connection.select_value(sql) : connection.exec_update(sql)
  end

  def select(sql, record_class, values) = connection.select_rows(inline(sql, record_class, values)).first
end

# Passes the values as binds, which ActiveRecord prepares when +prepare+ is true.
class SqlBindStatements < SqlStatements
  def initialize(prepare:)
    super()
    @prepare = prepare
  end

  private

  def binds(record_class, values)
    values.map do |column, value|
      name = column_name(column)
      ActiveRecord::Relation::QueryAttribute.new(name, value, record_class.type_for_attribute(name))
    end
  end

  def execute(sql, record_class, values, returning: false)
    result = connection.exec_query(sql, 'SQL', binds(record_class, values), prepare: @prepare)
    returning ? result.rows.first.first : result.length
  end

  def select(sql, record_class, values)
    connection.exec_query(sql, 'SQL', binds(record_class, values), prepare: @prepare).rows.first
  end
end

# Passes the values as parameters to the pg gem directly, preparing the statements when +prepare+ is true.
class PgStatements < SqlStatements
  def initialize(prepare:)
    super()
    @prepare = prepare
    @prepared = {}
  end

  private

  def params(record_class, values)
    serialized(record_class, values).map { |value| connection.type_cast(value) }
  end

  def run(sql, params)
    raw = connection.raw_connection
    return raw.exec_params(sql, params) unless @prepare

    name = @prepared[sql] ||= "benchmark_#{object_id}_#{@prepared.size}".tap { |statement| raw.prepare(statement, sql) }
    raw.exec_prepared(name, params)
  end

  def execute(sql, record_class, values, returning: false)
    result = run(sql, params(record_class, values))
    returning ? result.getvalue(0, 0) : result.cmd_tuples
  end

  def select(sql, record_class, values)
    result = run(sql, params(record_class, values))
    result.ntuples.zero? ? nil : result.values.first
  end
end

PERSISTORS = {
  active_record: -> { Sequent::Core::Persistors::ActiveRecordPersistor.new },
  unbuffered: -> { Sequent::Core::Persistors::UnbufferedPersistor.new },
  sql_literals: -> { StructPersistor.new(SqlLiteralStatements.new) },
  sql_binds: -> { StructPersistor.new(SqlBindStatements.new(prepare: false)) },
  sql_prepared: -> { StructPersistor.new(SqlBindStatements.new(prepare: true)) },
  pg_params: -> { StructPersistor.new(PgStatements.new(prepare: false)) },
  pg_prepared: -> { StructPersistor.new(PgStatements.new(prepare: true)) },
}.freeze

def project(persistor, aggregate_ids, created_at)
  aggregate_ids.each_slice(AGGREGATES_PER_TRANSACTION) do |slice|
    ActiveRecord::Base.transaction do
      slice.each_with_index do |aggregate_id, index|
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
        persistor.delete_all_records(BenchmarkRecord, aggregate_id:) if (index % 10).zero?
      end
    end
  end
end

def verify!(variant)
  expected_count = AGGREGATES - (0...AGGREGATES).count { |i| (i % AGGREGATES_PER_TRANSACTION % 10).zero? }
  rows = BenchmarkRecord.pluck(:sequence_number, :name, :description, :amount, :active, :tags, :payload).uniq
  expected = [
    [
      UPDATES_PER_AGGREGATE + 2,
      "name #{UPDATES_PER_AGGREGATE - 1}",
      'updated',
      BigDecimal(UPDATES_PER_AGGREGATE - 1),
      (UPDATES_PER_AGGREGATE - 1).even?,
      %w[a b],
      {'k' => 1},
    ],
  ]
  count = BenchmarkRecord.count
  fail "#{variant}: #{count} records instead of #{expected_count}" unless count == expected_count
  fail "#{variant}: unexpected records #{rows.inspect}" unless rows == expected
end

clock = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
aggregate_ids = Array.new(AGGREGATES) { SecureRandom.uuid }
created_at = Time.now
operations = (AGGREGATES * (UPDATES_PER_AGGREGATE + 3)) + (AGGREGATES / 10)

puts "#{AGGREGATES} aggregates, #{operations} operations, best of #{RUNS} runs"
(VARIANTS || PERSISTORS.keys).each do |variant|
  results = Array.new(RUNS) do
    BenchmarkRecord.connection.execute('TRUNCATE benchmark_records')
    persistor = PERSISTORS.fetch(variant).call
    GC.start
    allocations = GC.stat(:total_allocated_objects)
    started = clock.call
    project(persistor, aggregate_ids, created_at)
    elapsed = clock.call - started
    allocations = GC.stat(:total_allocated_objects) - allocations
    verify!(variant)
    {elapsed:, allocations:}
  end
  elapsed = results.map { |result| result[:elapsed] }.min
  allocations = results.map { |result| result[:allocations] }.min
  puts format(
    '%-14s %7.0f ms  %6.1f µs/operation  %6.1f allocations/operation',
    variant,
    elapsed * 1000,
    elapsed / operations * 1e6,
    allocations.to_f / operations,
  )
end
