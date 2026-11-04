# frozen_string_literal: true

require 'spec_helper'

class PersistorMethodsRecord < Sequent::ApplicationRecord; end

# The persistors that read records project the same data using the same methods. The ActiveRecordPersistor is the
# reference, and the exceptions are documented below.
describe 'Persistors reading and updating records' do
  let(:record_class) { PersistorMethodsRecord }
  let(:aggregate_id) { Sequent.new_uuid }
  let(:other_aggregate_id) { Sequent.new_uuid }
  let(:created_at) { Time.utc(2026, 1, 1) }
  let(:event_created_at) { Time.utc(2026, 1, 2) }
  let(:event) do
    Sequent::Core::Event.new(aggregate_id:, sequence_number: 3, created_at: event_created_at)
  end

  before do
    exec_sql(<<~SQL)
      DROP TABLE IF EXISTS persistor_methods_records;
      CREATE TABLE persistor_methods_records (
        id bigserial PRIMARY KEY,
        aggregate_id uuid NOT NULL,
        sequence_number integer NOT NULL,
        name character varying,
        amount integer,
        created_at timestamp without time zone NOT NULL,
        updated_at timestamp without time zone NOT NULL
      );
    SQL
    record_class.reset_column_information
  end

  def create(name, aggregate_id: self.aggregate_id, amount: nil)
    persistor.create_record(record_class, aggregate_id:, sequence_number: 1, name:, amount:, created_at:)
  end

  def stored(*columns) = record_class.order(:id).pluck(*columns)

  shared_examples 'a persistor reading and updating records' do |except: []|
    it 'reads the records in the order of their primary key' do
      create('a')
      create('b')
      create('c', aggregate_id: other_aggregate_id)

      expect(persistor.get_record(record_class, aggregate_id:).name).to eq 'a'
      expect(persistor.get_record!(record_class, aggregate_id:).name).to eq 'a'
      expect(persistor.last_record(record_class, aggregate_id:).name).to eq 'b'
      expect(persistor.find_records(record_class, aggregate_id:).map(&:name)).to match_array %w[a b]
      expect(persistor.find_records(record_class, name: %w[a c]).map(&:name)).to match_array %w[a c]
    end

    it 'does not find records that do not exist' do
      expect(persistor.get_record(record_class, aggregate_id:)).to be_nil
      expect(persistor.last_record(record_class, aggregate_id:)).to be_nil
      expect(persistor.find_records(record_class, aggregate_id:).to_a).to be_empty
      expect { persistor.get_record!(record_class, aggregate_id:) }.to raise_error(StandardError)
      expect { persistor.update_record(record_class, event) }.to raise_error(StandardError)
    end

    it 'updates a record with the time and sequence number of the event' do
      create('a')
      persistor.update_record(record_class, event) { |record| record.name = 'b' }
      persistor.flush

      expect(stored(:name, :sequence_number, :updated_at)).to eq [['b', 3, event_created_at]]
    end

    it 'updates a record without its sequence number when asked' do
      create('a')
      persistor.update_record(record_class, event, {aggregate_id:}, update_sequence_number: false)
      persistor.flush

      expect(stored(:sequence_number, :updated_at)).to eq [[1, event_created_at]]
    end

    it 'updates the record found by the where clause' do
      create('a')
      create('b')
      persistor.update_record(record_class, event, {aggregate_id:, name: 'b'}) { |record| record.amount = 2 }
      persistor.flush

      expect(stored(:name, :amount)).to eq [['a', nil], ['b', 2]]
    end

    it 'creates a record using create_or_update_record when it does not exist, and updates it otherwise' do
      persistor.create_or_update_record(record_class, {aggregate_id:, sequence_number: 1}, created_at) do |record|
        record.name = 'a'
      end
      persistor.create_or_update_record(record_class, {aggregate_id:}, created_at) { |record| record.amount = 2 }
      persistor.flush

      expect(stored(:name, :amount, :created_at)).to eq [['a', 2, created_at]]
    end

    it 'updates records using do_with_records and do_with_record' do
      create('a')
      create('b')
      create('c', aggregate_id: other_aggregate_id)
      persistor.do_with_records(record_class, aggregate_id:) { |record| record.amount = 1 }
      persistor.do_with_record(record_class, name: 'c') { |record| record.amount = 2 }
      persistor.flush

      expect(stored(:name, :amount)).to eq [['a', 1], ['b', 1], ['c', 2]]
    end

    it 'updates and deletes records using a where clause' do
      create('a')
      create('b')
      create('c', aggregate_id: other_aggregate_id)
      persistor.update_all_records(record_class, {aggregate_id:}, {amount: 3})
      persistor.delete_all_records(record_class, name: 'b')
      persistor.flush

      expect(stored(:name, :amount)).to eq [['a', 3], ['c', nil]]
    end

    it 'deletes a record using delete_record' do
      create('a')
      create('b')
      persistor.delete_record(record_class, persistor.get_record!(record_class, name: 'a'))
      persistor.flush

      expect(stored(:name)).to eq ['b']
    end

    it 'does not change a record when a block assigns the values it already has' do
      create('a', amount: 1)
      persistor.do_with_record(record_class, aggregate_id:) do |record|
        record.name = 'a'
        record.amount = '1'
      end
      persistor.flush

      expect(stored(:updated_at)).to eq [created_at]
    end

    unless except.include?(:touch_updated_at)
      it 'sets updated_at to the current time when a block changes a record without changing updated_at' do
        create('a')
        persistor.do_with_record(record_class, aggregate_id:) { |record| record.name = 'b' }
        persistor.flush

        expect(stored(:updated_at).sole).to be_within(1.minute).of(Time.now)
      end
    end
  end

  context Sequent::Core::Persistors::ActiveRecordPersistor do
    let(:persistor) { Sequent::Core::Persistors::ActiveRecordPersistor.new }

    it_behaves_like 'a persistor reading and updating records'
  end

  context Sequent::Core::Persistors::UnbufferedPersistor do
    let(:persistor) { Sequent::Core::Persistors::UnbufferedPersistor.new }

    it_behaves_like 'a persistor reading and updating records'

    it 'sets the primary key of a created record' do
      record = create('a')

      expect(record.id).to eq stored(:id).sole
    end
  end

  context Sequent::Core::Persistors::ReplayOptimizedPostgresPersistor do
    let(:persistor) { Sequent::Core::Persistors::ReplayOptimizedPostgresPersistor.new }

    # Known difference: the records are kept in memory, and a changed record keeps its updated_at.
    it_behaves_like 'a persistor reading and updating records', except: [:touch_updated_at]

    it 'keeps updated_at when a block changes a record without changing updated_at' do
      create('a')
      persistor.do_with_record(record_class, aggregate_id:) { |record| record.name = 'b' }
      persistor.flush

      expect(stored(:updated_at)).to eq [created_at]
    end
  end
end
