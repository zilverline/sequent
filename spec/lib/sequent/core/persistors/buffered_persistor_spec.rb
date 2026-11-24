# frozen_string_literal: true

require 'spec_helper'

describe Sequent::Core::Persistors::BufferedPersistor do
  class BufferedPersistorTest < Sequent::ApplicationRecord; end
  class OtherBufferedPersistorTest < Sequent::ApplicationRecord; end

  let(:record_class) { BufferedPersistorTest }
  let(:other_record_class) { OtherBufferedPersistorTest }
  let(:persistor) { described_class.new }
  let(:created_at) { Time.utc(2026, 1, 2, 3, 4, 5) }

  before do
    %w[buffered_persistor_tests other_buffered_persistor_tests].each do |table_name|
      Sequent::ApplicationRecord.connection.execute(<<~SQL)
        CREATE TABLE #{table_name} (
          id bigserial PRIMARY KEY,
          aggregate_id character varying NOT NULL,
          sequence_number integer,
          name character varying,
          amount numeric(12, 2),
          status character varying NOT NULL DEFAULT 'new',
          created_at timestamp with time zone NOT NULL DEFAULT now()
        )
      SQL
    end
    [record_class, other_record_class].each(&:reset_column_information)
  end

  after do
    persistor.clear
    Sequent::ApplicationRecord.connection.execute('DROP TABLE buffered_persistor_tests, other_buffered_persistor_tests')
    [record_class, other_record_class].each(&:reset_column_information)
  end

  def rows(clazz = record_class)
    clazz.pluck(:aggregate_id, :sequence_number, :name, :amount).sort_by(&:inspect)
  end

  def statements(&block)
    executed = []
    callback = ->(*, payload) do
      executed << payload[:sql] unless %w[SCHEMA TRANSACTION].include?(payload[:name])
    end
    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record', &block)
    executed
  end

  it 'only writes to the database when flushed' do
    persistor.create_record(record_class, created_at:, aggregate_id: 'a', sequence_number: 1)
    persistor.update_all_records(record_class, {aggregate_id: 'a'}, {name: 'x'})

    expect(rows).to be_empty

    persistor.flush

    expect(rows).to eq [['a', 1, 'x', nil]]
    expect(persistor.pending_statements).to eq 0
  end

  describe 'combining statements' do
    it 'inserts records created in the same table with a single statement' do
      persistor.create_record(record_class, created_at:, aggregate_id: 'a', name: 'x')
      persistor.create_records(
        record_class,
        [{created_at:, aggregate_id: 'b', name: 'y'}, {created_at:, aggregate_id: 'c', name: 'z'}],
      )

      expect(statements { persistor.flush }).to contain_exactly(/INSERT INTO "buffered_persistor_tests"/)
      expect(rows).to eq [['a', nil, 'x', nil], ['b', nil, 'y', nil], ['c', nil, 'z', nil]]
    end

    it 'inserts records with different columns using a statement per columns, in order' do
      persistor.create_record(record_class, created_at:, aggregate_id: 'a')
      persistor.create_record(record_class, created_at:, aggregate_id: 'b', name: 'y')
      persistor.create_record(record_class, created_at:, aggregate_id: 'c', name: 'z')

      expect(statements { persistor.flush }.size).to eq 2
      expect(rows).to eq [['a', nil, nil, nil], ['b', nil, 'y', nil], ['c', nil, 'z', nil]]
    end

    it 'inserts records with and without a value for a column with a default in order' do
      persistor.create_record(record_class, created_at:, aggregate_id: 'a', id: 100)
      persistor.create_record(record_class, created_at:, aggregate_id: 'b')

      persistor.flush

      expect(record_class.order(:aggregate_id).pluck(:aggregate_id, :id).first).to eq ['a', 100]
      expect(record_class.find_by(aggregate_id: 'b').id).to be_present
    end

    it 'combines updates whose where clauses and updates use symbols and strings' do
      persistor.create_record(record_class, created_at:, aggregate_id: 'a')
      persistor.update_all_records(record_class, {aggregate_id: 'a'}, {name: 'x'})
      persistor.update_all_records(record_class, {'aggregate_id' => 'a'}, {'sequence_number' => 3})

      expect(persistor.pending_statements).to eq 2
      expect(statements { persistor.flush }.size).to eq 2
      expect(rows).to eq [['a', 3, 'x', nil]]
    end

    it 'executes updates that ActiveRecord handles in order, without combining or moving them' do
      persistor.create_record(record_class, created_at:, aggregate_id: 'a', sequence_number: 1)
      persistor.update_all_records(record_class, {sequence_number: 1..2}, {name: 'x'})
      persistor.update_all_records(record_class, {sequence_number: 1..2}, {amount: 1})
      persistor.update_all_records(record_class, {aggregate_id: 'a'}, {sequence_number: 5})

      expect(persistor.pending_statements).to eq 4
      persistor.flush
      expect(rows).to eq [['a', 5, 'x', 1]]
    end

    it 'prepares the updates and deletes' do
      persistor.create_record(record_class, created_at:, aggregate_id: 'a')
      persistor.update_all_records(record_class, {aggregate_id: 'a'}, {name: 'x'})
      persistor.delete_all_records(record_class, {aggregate_id: 'b'})
      names = []
      callback = ->(*, payload) { names << payload[:statement_name] if payload[:name] =~ /(Update|Delete)\z/ }
      ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') { persistor.flush }

      expect(names.size).to eq 2
      expect(names).to all(be_present)
    end

    it 'combines updates of the same records' do
      persistor.create_record(record_class, created_at:, aggregate_id: 'a', sequence_number: 1)
      10.times do |i|
        persistor.update_all_records(record_class, {aggregate_id: 'a'}, {name: "name #{i}", sequence_number: i + 2})
      end
      persistor.update_all_records(record_class, {aggregate_id: 'a'}, {amount: 5})

      expect(statements { persistor.flush }.size).to eq 2
      expect(rows).to eq [['a', 11, 'name 9', 5]]
    end

    it 'combines updates of the same records with updates of other records in between' do
      persistor.update_all_records(record_class, {aggregate_id: 'a'}, {name: 'x'})
      persistor.update_all_records(record_class, {aggregate_id: 'b'}, {name: 'y'})
      persistor.update_all_records(record_class, {aggregate_id: 'a'}, {amount: 1})

      expect(persistor.pending_statements).to eq 2
    end

    it 'does not combine updates when an update in between changes the same column' do
      persistor.update_all_records(record_class, {aggregate_id: 'a'}, {name: 'x'})
      persistor.update_all_records(record_class, {sequence_number: 1}, {name: 'y'})
      persistor.update_all_records(record_class, {aggregate_id: 'a'}, {name: 'z'})

      expect(persistor.pending_statements).to eq 3
    end

    it 'does not combine updates that change a column of their where clause' do
      persistor.update_all_records(record_class, {name: 'x'}, {name: 'y'})
      persistor.update_all_records(record_class, {name: 'x'}, {amount: 1})

      expect(persistor.pending_statements).to eq 2
    end

    it 'does not move an update before a record that it may update' do
      persistor.update_all_records(record_class, {aggregate_id: 'a'}, {name: 'x'})
      persistor.create_record(record_class, created_at:, aggregate_id: 'a')
      persistor.update_all_records(record_class, {aggregate_id: 'a'}, {name: 'y'})

      expect(persistor.pending_statements).to eq 3
      persistor.flush
      expect(rows).to eq [['a', nil, 'y', nil]]
    end

    it 'combines statements for a table with statements for other tables in between' do
      persistor.create_record(record_class, created_at:, aggregate_id: 'a')
      persistor.create_record(other_record_class, created_at:, aggregate_id: 'a')
      persistor.create_record(record_class, created_at:, aggregate_id: 'b')

      expect(persistor.pending_statements).to eq 2
    end

    it 'executes updates using SQL in order' do
      persistor.create_record(record_class, created_at:, aggregate_id: 'a', amount: 1)
      persistor.update_all_records(record_class, {aggregate_id: 'a'}, 'amount = amount * 10')
      persistor.update_all_records(record_class, {aggregate_id: 'a'}, {amount: 2})
      persistor.update_all_records(record_class, {aggregate_id: 'a'}, 'amount = amount + 1')

      persistor.flush

      expect(rows).to eq [['a', nil, nil, 3]]
    end
  end

  describe 'compared to the ActiveRecordPersistor' do
    COLUMNS = %i[aggregate_id sequence_number name amount].freeze

    def random_value(random, column)
      case column
      when :aggregate_id then %w[a b c].sample(random:)
      when :sequence_number then [1, 2, 3, nil].sample(random:)
      when :name then ['x', 'y', nil].sample(random:)
      when :amount then [1, BigDecimal('2.5'), nil].sample(random:)
      end
    end

    def random_values(random, columns)
      columns.sample(random.rand(1..columns.size), random:).to_h { |column| [column, random_value(random, column)] }
    end

    # Mostly where clauses from a small set, so the same records are updated often and statements are combined.
    WHERE_CLAUSES = [
      {aggregate_id: 'a'},
      {aggregate_id: 'b'},
      {aggregate_id: 'a', sequence_number: 1},
      {aggregate_id: %w[a b]},
      {name: 'x'},
      {sequence_number: nil},
    ].freeze

    def random_where_clause(random)
      return WHERE_CLAUSES.sample(random:) if random.rand < 0.7

      random_values(random, COLUMNS).to_h do |column, value|
        next [column, value] unless random.rand < 0.2

        [column, [value, random_value(random, column)].uniq]
      end
    end

    # Generates all arguments up front, so both persistors get the same operations.
    def random_operation(random)
      case random.rand(100)
      when 0...25
        values = {created_at:, aggregate_id: random_value(random, :aggregate_id)}
          .merge(random_values(random, COLUMNS - [:aggregate_id]))
        ->(persistor) { persistor.create_record(record_class, values) }
      when 25...35
        # All rows have the same columns, as required by insert_all.
        columns = %i[created_at aggregate_id] + %i[sequence_number name amount].sample(random.rand(0..3), random:)
        rows = Array.new(random.rand(1..3)) do
          columns.to_h { |column| [column, column == :created_at ? created_at : random_value(random, column)] }
        end
        ->(persistor) { persistor.create_records(record_class, rows) }
      when 35...80
        where_clause = random_where_clause(random)
        updates = random_values(random, COLUMNS - [:aggregate_id])
        ->(persistor) { persistor.update_all_records(record_class, where_clause, updates) }
      when 80...85
        where_clause = random_where_clause(random)
        ->(persistor) { persistor.update_all_records(record_class, where_clause, 'amount = coalesce(amount, 0) + 1') }
      else
        where_clause = random_where_clause(random)
        ->(persistor) { persistor.delete_all_records(record_class, where_clause) }
      end
    end

    60.times do |seed|
      it "has the same outcome for random operations (seed #{seed})" do
        random = Random.new(seed)
        operations = Array.new(40) { random_operation(random) }
        flush_after = operations.each_index.select { random.rand < 0.15 }.to_set

        active_record_persistor = Sequent::Core::Persistors::ActiveRecordPersistor.new
        operations.each { |operation| operation.call(active_record_persistor) }
        expected = rows
        record_class.delete_all

        operations.each_with_index do |operation, i|
          operation.call(persistor)
          persistor.flush if flush_after.include?(i)
        end
        persistor.flush

        expect(rows).to eq expected
      end
    end
  end

  describe 'created records' do
    it 'are structs with the column defaults of the record class' do
      record = persistor.create_record(record_class, created_at:, aggregate_id: 'a')

      expect(record).to be_a Struct
      expect(record.status).to eq 'new'
      expect(record.created_at).to eq created_at
    end

    it 'leave the columns without a value and without a known default to the database' do
      persistor.create_record(record_class, created_at:, aggregate_id: 'a')
      persistor.flush

      expect(record_class.find_by(aggregate_id: 'a')).to have_attributes(status: 'new', created_at:)
    end

    it 'are passed to the block of create_record' do
      persistor.create_record(record_class, created_at:, aggregate_id: 'a') { |record| record.name = 'x' }
      persistor.flush

      expect(rows).to eq [['a', nil, 'x', nil]]
    end

    it 'leave a column without a known default given nil to the database, like ActiveRecord' do
      persistor.create_record(record_class, created_at:, aggregate_id: 'a', id: nil)
      persistor.flush

      expect(record_class.find_by(aggregate_id: 'a').id).to be_present
    end

    it 'write NULL for a column with a known default given nil, like ActiveRecord' do
      persistor.create_record(record_class, created_at:, aggregate_id: 'a', status: nil)

      expect { persistor.flush }.to raise_error(ActiveRecord::NotNullViolation)
    end
  end

  describe 'reading' do
    let(:event) { Struct.new(:aggregate_id, :sequence_number, :created_at).new('a', 7, created_at) }

    it 'reads a table without pending changes without flushing' do
      persistor.create_record(other_record_class, created_at:, aggregate_id: 'o')

      expect(statements { expect(persistor.get_record(record_class, aggregate_id: 'a')).to be_nil }.size).to eq 1
      expect(persistor.pending_statements).to eq 1
      expect(persistor.read_flushes).to eq 0
    end

    it 'flushes the whole buffer in order before reading a table with pending changes' do
      persistor.create_record(other_record_class, created_at:, aggregate_id: 'o')
      persistor.create_record(record_class, created_at:, aggregate_id: 'a', name: 'x')
      persistor.update_all_records(other_record_class, {aggregate_id: 'o'}, {name: 'y'})

      record = persistor.get_record!(record_class, aggregate_id: 'a')

      expect(record.name).to eq 'x'
      expect(record.id).to be_present
      expect(persistor.pending_statements).to eq 0
      expect(persistor.read_flushes).to eq 1
      expect(rows(other_record_class)).to eq [['o', nil, 'y', nil]]
    end

    it 'reads with find_records and last_record after flushing' do
      persistor.create_records(record_class, [{created_at:, aggregate_id: 'a'}, {created_at:, aggregate_id: 'a'}])

      expect(persistor.find_records(record_class, aggregate_id: 'a').size).to eq 2
      first = persistor.get_record(record_class, aggregate_id: 'a')
      expect(persistor.last_record(record_class, aggregate_id: 'a').id).to be > first.id
      expect(persistor.read_flushes).to eq 1
    end

    it 'fails like the other persistors when get_record! finds nothing' do
      expect { persistor.get_record!(record_class, aggregate_id: 'a') }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it 'fails when update_record finds nothing' do
      expect { persistor.update_record(record_class, event) { |_| } }.to raise_error(/not found/)
    end

    it 'buffers the update of update_record by primary key, for the changed columns' do
      persistor.create_record(record_class, created_at:, aggregate_id: 'a', sequence_number: 1)

      persistor.update_record(record_class, event) { |record| record.name = 'x' }

      expect(persistor.pending_statements).to eq 1
      expect(rows).to eq [['a', 1, nil, nil]]

      persistor.flush

      expect(rows).to eq [['a', 7, 'x', nil]]
    end

    it 'combines the update of update_record with a later update of the same record' do
      persistor.create_record(record_class, created_at:, aggregate_id: 'a', sequence_number: 1)
      record = persistor.update_record(record_class, event) { |r| r.name = 'x' }
      persistor.update_all_records(record_class, {id: record.id}, {amount: 5})

      expect(persistor.pending_statements).to eq 1
      expect(statements { persistor.flush }.size).to eq 1
      expect(rows).to eq [['a', 7, 'x', 5]]
    end

    it 'does not buffer anything when update_record changes nothing' do
      persistor.create_record(record_class, created_at:, aggregate_id: 'a', sequence_number: 7)

      persistor.update_record(record_class, event)

      expect(persistor.pending_statements).to eq 0
    end

    it 'supports do_with_record, do_with_records and create_or_update_record' do
      persistor.create_records(record_class, [{created_at:, aggregate_id: 'a'}, {created_at:, aggregate_id: 'b'}])
      persistor.do_with_record(record_class, aggregate_id: 'a') { |record| record.name = 'x' }
      persistor.do_with_records(record_class, {}) { |record| record.amount = 1 }
      persistor.create_or_update_record(record_class, {aggregate_id: 'c'}, created_at) { |_| }
      persistor.create_or_update_record(record_class, {aggregate_id: 'b'}) { |record| record.status = 'old' }
      persistor.flush

      expect(rows).to eq [['a', nil, 'x', 1], ['b', nil, nil, 1], ['c', nil, nil, nil]]
      expect(record_class.where(aggregate_id: 'b').pick(:status)).to eq 'old'
    end

    it 'deletes a record read earlier by primary key' do
      persistor.create_record(record_class, created_at:, aggregate_id: 'a')
      persistor.create_record(record_class, created_at:, aggregate_id: 'b')
      persistor.delete_record(record_class, persistor.get_record!(record_class, aggregate_id: 'a'))
      persistor.flush

      expect(rows).to eq [['b', nil, nil, nil]]
    end

    it 'flushes before execute_sql' do
      persistor.create_record(record_class, created_at:, aggregate_id: 'a')
      persistor.execute_sql('UPDATE buffered_persistor_tests SET name = \'sql\'')

      expect(rows).to eq [['a', nil, 'sql', nil]]
    end
  end

  it 'keeps a buffer per instance' do
    persistor.create_record(record_class, created_at:, aggregate_id: 'a')

    expect(described_class.new.pending_statements).to eq 0
    expect(persistor.pending_statements).to eq 1
  end
end
