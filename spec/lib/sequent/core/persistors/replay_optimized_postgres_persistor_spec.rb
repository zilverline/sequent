# frozen_string_literal: true

require 'spec_helper'
require 'sequent/support'
require 'tmpdir'

require_relative '../../migration_class'

class MockEvent < Sequent::Core::Event
  def initialize
    super(aggregate_id: 'foo', sequence_number: 1)
  end
end

def measure_elapsed_time(&block)
  starting = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  yield block
  ending = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  ending - starting
end

describe Sequent::Core::Persistors::ReplayOptimizedPostgresPersistor do
  let(:indices) { {} }
  let(:persistor) { Sequent::Core::Persistors::ReplayOptimizedPostgresPersistor.new(50, indices) }
  let(:record_class) { Sequent::Core::EventRecord }
  let(:mock_event) { MockEvent.new }

  context '#get_record!' do
    it 'fails when no object is found' do
      expect { persistor.get_record!(record_class, {aggregate_id: 1}) }
        .to raise_error(/record #{record_class} not found}*/)
    end
  end

  context '#update_record' do
    it 'fails when no object is found' do
      expect do
        persistor.update_record(record_class, mock_event, {aggregate_id: 1})
      end.to raise_error(/record #{record_class} not found}*/)
    end
  end

  context '#get_record' do
    it 'returns nil when no object is found' do
      expect(persistor.get_record(record_class, {aggregate_id: 1})).to be_nil
    end
  end

  context '#find_records' do
    it 'returns empty array when no objects are found' do
      expect(persistor.find_records(record_class, {aggregate_id: 1})).to be_empty
    end
  end

  context '#delete_all_records' do
    it 'does not fail when there is nothing to delete' do
      persistor.delete_all_records(record_class, {aggregate_id: 1})
    end
  end

  context '#delete_record' do
    it 'does not fail when there is nothing to delete' do
      persistor.delete_record(record_class, record_class.new(aggregate_id: 1))
    end
  end

  context '#update_all_records' do
    it 'does not fail when there is nothing to update' do
      persistor.update_all_records(record_class, {aggregate_id: 1}, {sequence_number: 2})
    end
  end

  it 'can save multiple objects at once' do
    persistor.create_records(Sequent::Core::EventRecord, [{aggregate_id: 1}, {aggregate_id: 2}])
    object = persistor.get_record!(record_class, {aggregate_id: 1})
    expect(object.aggregate_id).to eq 1
    object = persistor.get_record!(record_class, {aggregate_id: 2})
    expect(object.aggregate_id).to eq 2

    objects = persistor.find_records(record_class, {aggregate_id: [1, 2]})
    expect(objects).to have(2).items
  end

  context 'with an object' do
    before :each do
      persistor.create_record(Sequent::Core::EventRecord, {aggregate_id: 1})
    end

    context '#get_record!' do
      it 'returns the object' do
        object = persistor.get_record!(record_class, {aggregate_id: 1})
        expect(object.aggregate_id).to eq 1
      end
    end

    context '#get_record' do
      it 'returns the object' do
        object = persistor.get_record(record_class, {aggregate_id: 1})
        expect(object.aggregate_id).to eq 1
      end
    end

    context '#find_records' do
      it 'returns the object' do
        objects = persistor.find_records(record_class, {aggregate_id: 1})
        expect(objects).to have(1).item
        expect(objects.first.aggregate_id).to eq 1
      end
    end

    context '#delete_all_records' do
      it 'deletes the object' do
        persistor.delete_all_records(record_class, {aggregate_id: 1})

        objects = persistor.find_records(record_class, {aggregate_id: 1})
        expect(objects).to be_empty
      end
    end

    context '#delete_record' do
      it 'deletes the object' do
        objects = persistor.find_records(record_class, {aggregate_id: 1})
        persistor.delete_record(record_class, objects.first)

        expect(persistor.find_records(record_class, {aggregate_id: 1})).to be_empty
      end

      it 'ignores records that are not present' do
        persistor.delete_record(record_class, Object.new)
      end
    end

    context '#update_all_records' do
      it 'updates the records' do
        persistor.update_all_records(record_class, {aggregate_id: 1}, {sequence_number: 3})

        objects = persistor.find_records(record_class, {aggregate_id: 1})
        expect(objects).to have(1).item
        expect(objects.first.aggregate_id).to eq 1
        expect(objects.first.sequence_number).to eq 3
      end
    end
  end

  context 'value normalization' do
    before :each do
      persistor.create_record(record_class, {aggregate_id: 1, event_type: :SymbolEvent})
      persistor.create_record(record_class, {aggregate_id: 2, event_type: 'StringEvent'})
    end

    context 'when using an index' do
      let(:indices) { {record_class => [:event_type]} }

      it 'should find records with symbol values using strings' do
        objects = persistor.find_records(record_class, {event_type: 'SymbolEvent'})
        expect(objects).to have(1).item
      end

      it 'should find records with string values using symbol' do
        objects = persistor.find_records(record_class, {event_type: :StringEvent})
        expect(objects).to have(1).item
      end
    end

    context 'when not using an index' do
      it 'should find records with symbol values using strings' do
        objects = persistor.find_records(record_class, {event_type: 'SymbolEvent'})
        expect(objects).to have(1).item
      end

      it 'should find records with string values using symbol' do
        objects = persistor.find_records(record_class, {event_type: :StringEvent})
        expect(objects).to have(1).item
      end
    end
  end

  context 'committing' do
    class ReplayOptimizedPostgresTest < Sequent::ApplicationRecord; end

    let(:migrations_path) { File.expand_path(database_name, Dir.tmpdir).tap { |dir| Dir.mkdir(dir) } }
    let(:database_name) { Sequent.new_uuid }
    let(:db_config) do
      Database.test_config.merge(
        'database' => database_name,
      )
    end
    let(:database) { Sequent::Support::Database.new }
    let(:persistor) { Sequent::Core::Persistors::ReplayOptimizedPostgresPersistor.new(insert_csv_size) }

    before do
      Sequent::Support::Database.create!(db_config)
      Sequent::Support::Database.establish_connection(db_config)
    end

    after do
      Sequent::Support::Database.drop!(db_config)
      Sequent::Support::Database.disconnect!
    end

    before :each do
      Sequent::ApplicationRecord.connection.execute(<<~SQL)
        CREATE TABLE if not exists replay_optimized_postgres_tests
            (
                name character varying,
                initials character varying[] default '{}',
                created_at timestamp without time zone,
                updated_at timestamp without time zone
            )
      SQL
    end

    after :each do
      Sequent::ApplicationRecord.connection.execute('drop table if exists replay_optimized_postgres_tests')
    end

    context 'csv' do
      let(:insert_csv_size) { 0 }
      let(:values) { {name: 'bén', initials: ['björ'], created_at: DateTime.now} }

      context 'values as with_indifferent_access' do
        it 'commits a persistor' do
          persistor.create_record(ReplayOptimizedPostgresTest, values.with_indifferent_access)
          expect { persistor.commit }.to change { ReplayOptimizedPostgresTest.count }.by(1)
        end
      end

      context 'values as normal hashes' do
        it 'commits a persistor' do
          persistor.create_record(ReplayOptimizedPostgresTest, values)
          expect { persistor.commit }.to change { ReplayOptimizedPostgresTest.count }.by(1)
        end
      end

      context 'lots of values' do
        let(:values) do
          10_000.times.map do |i|
            {name: "Ben #{i}", initials: ['b'], created_at: DateTime.now}
          end
        end

        it 'commits a persistor' do
          persistor.create_records(ReplayOptimizedPostgresTest, values)
          expect { persistor.commit }.to change { ReplayOptimizedPostgresTest.count }.by(10_000)
        end
      end
    end

    context 'batch inserts' do
      let(:insert_csv_size) { 1 }
      let(:values) { {name: 'ben', initials: ['b'], created_at: DateTime.now} }

      context 'values as with_indifferent_access' do
        it 'commits a persistor' do
          persistor.create_record(ReplayOptimizedPostgresTest, values.with_indifferent_access)

          expect { persistor.commit }.to change { ReplayOptimizedPostgresTest.count }.by(1)
        end
      end

      context 'values as normal hashes' do
        it 'commits a persistor' do
          persistor.create_record(ReplayOptimizedPostgresTest, values)

          expect { persistor.commit }.to change { ReplayOptimizedPostgresTest.count }.by(1)
        end
      end
    end
  end

  context 'with some records' do
    let(:aggregate_id) { Sequent.new_uuid }
    before :each do
      persistor.create_record(Sequent::Core::EventRecord, {aggregate_id: 1, command_record_id: 2})
      persistor.create_record(Sequent::Core::EventRecord, {aggregate_id: 1, sequence_number: 2})
      persistor.create_record(Sequent::Core::EventRecord, {aggregate_id: aggregate_id, command_record_id: 2})
    end

    let(:persistor) do
      Sequent::Core::Persistors::ReplayOptimizedPostgresPersistor.new(
        50,
        {
          Sequent::Core::EventRecord => %i[id command_record_id sequence_number],
        },
      )
    end

    context '#find_records' do
      let(:records) { persistor.find_records(record_class, where_clause) }

      context 'finding multiple records' do
        let(:where_clause) { {aggregate_id: 1} }

        it 'returns the correct number records' do
          expect(records).to have(2).items
        end
      end

      context 'finding array valued where-clause' do
        let(:where_clause) { {aggregate_id: [1, aggregate_id]} }

        it 'returns the correct number records' do
          expect(records).to have(3).items
        end
      end

      context 'with an indexed where clause' do
        let(:where_clause) { {aggregate_id: 1, command_record_id: 2} }
        it 'returns the correct number records' do
          expect(records).to have(1).item
        end

        it 'returns the correct record' do
          expect(records.first.aggregate_id).to eq 1
          expect(records.first.command_record_id).to eq 2
          expect(records.first.sequence_number).to be_nil
        end
      end

      context 'stringified indexed where clause' do
        let(:where_clause) { {'aggregate_id' => 1, 'command_record_id' => 2} }

        it 'returns the correct number records' do
          expect(records).to have(1).item
        end

        it 'returns the correct record' do
          expect(records.first.aggregate_id).to eq 1
          expect(records.first.command_record_id).to eq 2
          expect(records.first.sequence_number).to be_nil
        end
      end

      context 'arbitrary order in indexed where clause' do
        let(:where_clause) { {'command_record_id' => 2, 'aggregate_id' => 1} }

        it 'returns the correct number records' do
          expect(records).to have(1).item
        end

        it 'returns the correct record' do
          expect(records.first.aggregate_id).to eq 1
          expect(records.first.command_record_id).to eq 2
          expect(records.first.sequence_number).to be_nil
        end
      end

      context 'on aggregate_id' do
        let(:where_clause) { {aggregate_id: aggregate_id} }

        it 'returns the correct number records' do
          expect(records).to have(1).item
        end

        it 'returns the correct record' do
          expect(records.first.aggregate_id).to eq aggregate_id
        end
      end
    end

    context '#delete_all_records' do
      it 'deletes the object based on single column' do
        expect(persistor.find_records(record_class, {aggregate_id: 1})).to have(2).items

        persistor.delete_all_records(record_class, {aggregate_id: 1})

        expect(persistor.find_records(record_class, {aggregate_id: 1})).to be_empty
      end

      it 'deletes the object based on multiple columns with index' do
        expect(persistor.find_records(record_class, {aggregate_id: 1, command_record_id: 2})).to have(1).item

        persistor.delete_all_records(record_class, {aggregate_id: 1, command_record_id: 2})

        expect(persistor.find_records(record_class, {aggregate_id: 1, command_record_id: 2})).to be_empty
        expect(persistor.find_records(record_class, {aggregate_id: 1, sequence_number: 2})).to have(1).item
      end
    end

    context '#update_all_records' do
      it 'only updates the records adhering to the where clause' do
        persistor.update_all_records(record_class, {aggregate_id: 1, sequence_number: 2}, {command_record_id: 10})

        object = persistor.get_record!(record_class, {aggregate_id: 1, sequence_number: 2})
        expect(object.aggregate_id).to eq 1
        expect(object.command_record_id).to eq 10
      end

      context 'with an indexed where' do
        before do
          persistor.update_all_records(record_class, where_clause, {sequence_number: 99})
        end
        context 'in indexed order' do
          let(:where_clause) { {aggregate_id: 1, sequence_number: 2} }
          it 'can update an indexed column' do
            expect(persistor.get_record(record_class, {aggregate_id: 1, sequence_number: 2})).to be_nil

            object = persistor.get_record!(record_class, {aggregate_id: 1, sequence_number: 99})
            expect(object.aggregate_id).to eq 1
            expect(object.sequence_number).to eq 99
          end
        end

        context 'in reversed indexed order' do
          let(:where_clause) { {sequence_number: 2, 'aggregate_id' => 1} }
          it 'can update an indexed column' do
            expect(persistor.get_record(record_class, {aggregate_id: 1, sequence_number: 2})).to be_nil

            object = persistor.get_record!(record_class, {aggregate_id: 1, sequence_number: 99})
            expect(object.aggregate_id).to eq 1
            expect(object.sequence_number).to eq 99
          end
        end
      end

      it 'can update an indexed column' do
        persistor.update_all_records(record_class, {aggregate_id: 1, sequence_number: 2}, {sequence_number: 99})

        expect(persistor.get_record(record_class, {aggregate_id: 1, sequence_number: 2})).to be_nil

        object = persistor.get_record!(record_class, {aggregate_id: 1, sequence_number: 99})
        expect(object.aggregate_id).to eq 1
        expect(object.sequence_number).to eq 99
      end

      it 'can update an indexed column with reversed where' do
        persistor.update_all_records(record_class, {sequence_number: 2, aggregate_id: 1}, {sequence_number: 99})

        expect(persistor.get_record(record_class, {aggregate_id: 1, sequence_number: 2})).to be_nil

        object = persistor.get_record!(record_class, {aggregate_id: 1, sequence_number: 99})
        expect(object.aggregate_id).to eq 1
        expect(object.sequence_number).to eq 99
      end
    end

    context 'duplicate hash values' do
      let(:indices) { %i[aggregate_id] }
      class BadHash < Struct.new(:value)
        def hash
          0
        end
      end

      it 'should not match records even when hash collision occurs' do
        one = persistor.create_record(Sequent::Core::EventRecord, aggregate_id: BadHash.new(1), sequence_number: 1)
        two = persistor.create_record(Sequent::Core::EventRecord, aggregate_id: BadHash.new(2), sequence_number: 1)

        expect(persistor.find_records(Sequent::Core::EventRecord, {aggregate_id: one.aggregate_id}))
          .to match_array [one]
        expect(persistor.find_records(Sequent::Core::EventRecord, {aggregate_id: two.aggregate_id}))
          .to match_array [two]
      end
    end
  end

  context 'with thousands of records' do
    COUNT = 1000
    ITERATIONS = 10
    MAX_TIME_S = 1

    let(:persistor) do
      Sequent::Core::Persistors::ReplayOptimizedPostgresPersistor.new(
        50,
        {
          Sequent::Core::EventRecord => [%i[aggregate_id command_record_id], %i[aggregate_id sequence_number]],
        },
      )
    end
    let(:aggregate_ids) { (0...COUNT).map { Sequent.new_uuid } }

    before do
      aggregate_ids.each_with_index do |aggregate_id, i|
        persistor.create_record(
          Sequent::Core::EventRecord,
          {aggregate_id: aggregate_id, command_record_id: i * 7},
        )
      end
    end

    it 'performs well using an aggregate_id lookup' do
      elapsed = measure_elapsed_time do
        ITERATIONS.times do
          aggregate_ids.each do |aggregate_id|
            expect(persistor.get_record(Sequent::Core::EventRecord, {aggregate_id: aggregate_id})).to be_present
          end
        end
      end
      expect(elapsed).to be <= MAX_TIME_S
    end

    it 'performs well using a multi-index lookup' do
      elapsed = measure_elapsed_time do
        ITERATIONS.times do
          (0...COUNT).each do |i|
            expect(
              persistor.get_record(
                Sequent::Core::EventRecord,
                {aggregate_id: aggregate_ids[i], command_record_id: i * 7},
              ),
            ).to be_present
          end
        end
      end
      expect(elapsed).to be <= MAX_TIME_S
    end
  end

  describe Sequent::Core::Persistors::ReplayOptimizedPostgresPersistor::Index do
    let(:indices) { [] }
    let(:index) do
      Sequent::Core::Persistors::ReplayOptimizedPostgresPersistor::Index.new(indices)
    end

    describe '#use_index?' do
      context 'symbolized single indices' do
        let(:indices) { [:id] }
        it 'uses the index for simple indexed column' do
          expect(index.use_index?({id: 1})).to be_truthy
        end

        it 'does not use index for non indexed columns' do
          expect(index.use_index?({command_record_id: 1})).to be_falsey
        end
      end

      context 'multiple indices' do
        let(:indices) { %i[id command_record_id] }

        it 'uses the index for where clause' do
          expect(index.use_index?({id: 1})).to be_truthy
          expect(index.use_index?({command_record_id: 10})).to be_truthy
        end

        it 'use index for for partial indexed where clauses' do
          expect(index.use_index?({sequence_number: 1})).to be_falsey
          expect(index.use_index?({id: 1, sequence_number: 1})).to be_truthy
        end

        context 'duplicate indexes' do
          let(:indices) { %i[aggregate_id command_record_id id id command_record_id] }
          it 'are removed' do
            expect(index.indexed_columns).to match_array %i[aggregate_id command_record_id id]
          end
        end
      end

      context 'where clause order' do
        let(:indices) { %i[id command_record_id] }

        it 'uses the index for strings and symbols where clause' do
          expect(index.use_index?({command_record_id: 10, id: 1})).to be_truthy
        end
      end
    end
  end
end
