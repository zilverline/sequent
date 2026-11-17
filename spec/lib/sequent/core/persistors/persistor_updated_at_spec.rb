# frozen_string_literal: true

require 'spec_helper'

class PersistorUpdatedAtRecord < Sequent::ApplicationRecord; end

# A block that changes a record only changes its updated_at when the block sets it, so the projected updated_at does
# not depend on when the events are handled, and is the same after a replay.
describe 'Persistors updating records using a block' do
  let(:aggregate_id) { Sequent.new_uuid }
  let(:created_at) { Time.utc(2026, 1, 1) }
  let(:event_created_at) { Time.utc(2026, 1, 2) }

  before do
    exec_sql(<<~SQL)
      DROP TABLE IF EXISTS persistor_updated_at_records;
      CREATE TABLE persistor_updated_at_records (
        id bigserial PRIMARY KEY,
        aggregate_id uuid NOT NULL,
        sequence_number integer NOT NULL,
        name character varying,
        created_at timestamp without time zone NOT NULL,
        updated_at timestamp without time zone NOT NULL
      );
    SQL
    PersistorUpdatedAtRecord.reset_column_information
    persistor.create_record(
      PersistorUpdatedAtRecord,
      aggregate_id:,
      sequence_number: 1,
      name: 'a',
      created_at:,
    )
  end

  def stored = PersistorUpdatedAtRecord.pluck(:name, :updated_at).sole

  def event(created_at)
    Sequent::Core::Event.new(aggregate_id:, sequence_number: 2, created_at:)
  end

  shared_examples 'a persistor keeping updated_at' do
    it 'keeps updated_at when do_with_record changes a record' do
      persistor.do_with_record(PersistorUpdatedAtRecord, aggregate_id:) { |record| record.name = 'b' }
      persistor.flush

      expect(stored).to eq ['b', created_at]
    end

    it 'keeps updated_at when do_with_records changes a record' do
      persistor.do_with_records(PersistorUpdatedAtRecord, aggregate_id:) { |record| record.name = 'b' }
      persistor.flush

      expect(stored).to eq ['b', created_at]
    end

    it 'keeps updated_at when create_or_update_record changes an existing record' do
      persistor.create_or_update_record(PersistorUpdatedAtRecord, {aggregate_id:}) { |record| record.name = 'b' }
      persistor.flush

      expect(stored).to eq ['b', created_at]
    end

    it 'stores the updated_at that a block sets' do
      persistor.do_with_record(PersistorUpdatedAtRecord, aggregate_id:) do |record|
        record.name = 'b'
        record.updated_at = event_created_at
      end
      persistor.flush

      expect(stored).to eq ['b', event_created_at]
    end

    it 'stores the time of the event as updated_at using update_record, also when it is unchanged' do
      persistor.update_record(PersistorUpdatedAtRecord, event(created_at)) { |record| record.name = 'b' }
      persistor.flush

      expect(stored).to eq ['b', created_at]
    end
  end

  context Sequent::Core::Persistors::ActiveRecordPersistor do
    let(:persistor) { Sequent::Core::Persistors::ActiveRecordPersistor.new }

    it_behaves_like 'a persistor keeping updated_at'
  end

  context Sequent::Core::Persistors::ReplayOptimizedPostgresPersistor do
    let(:persistor) { Sequent::Core::Persistors::ReplayOptimizedPostgresPersistor.new }

    it_behaves_like 'a persistor keeping updated_at'
  end
end
