# frozen_string_literal: true

require 'spec_helper'

class PersistorDefaultsRecord < Sequent::ApplicationRecord; end

# A view on the table, like the temporary views used to rename a table or column without downtime. The database does
# not report the defaults of the table for the columns of the view, so ActiveRecord does not know them.
class PersistorDefaultsViewRecord < Sequent::ApplicationRecord
  self.table_name = 'persistor_defaults_view_records'
  self.primary_key = 'id'
end

# The persistors store the same values for columns without a value, explicit nils and updated columns. The
# ActiveRecordPersistor on a table is the reference, and the exceptions are documented below.
describe 'Persistors storing columns without a value' do
  let(:table) { PersistorDefaultsRecord }
  let(:uuid) { Sequent.new_uuid }
  let(:time) { Time.utc(2026, 1, 1) }

  before do
    exec_sql(<<~SQL)
      DROP VIEW IF EXISTS persistor_defaults_view_records;
      DROP TABLE IF EXISTS persistor_defaults_records;
      CREATE TABLE persistor_defaults_records (
        id bigserial PRIMARY KEY,
        serialid bigserial NOT NULL,
        name character varying,
        status character varying DEFAULT 'new',
        created_at timestamp with time zone NOT NULL DEFAULT now(),
        token uuid DEFAULT gen_random_uuid()
      );
      CREATE VIEW persistor_defaults_view_records AS SELECT * FROM persistor_defaults_records;
    SQL
    table.reset_column_information
    PersistorDefaultsViewRecord.reset_column_information
  end

  around do |example|
    partial_inserts = record_class.partial_inserts
    example.run
  ensure
    record_class.partial_inserts = partial_inserts
  end

  def stored(name, *columns)
    table.where(name:).pluck(*columns).sole
  end

  shared_examples 'a persistor storing columns without a value' do |except: []|
    unless except.include?(:explicit_nil)
      it 'stores NULL for an explicit nil in a column with a constant default' do
        persistor.create_record(record_class, name: 'a', status: nil)
        persistor.flush

        expect(stored('a', :status)).to be_nil
      end
    end

    it 'stores the database defaults of the columns without a value' do
      persistor.create_record(record_class, name: 'a')
      persistor.flush

      expect(stored('a', :id, :serialid, :created_at, :token)).to all(be_present)
      expect(stored('a', :status)).to eq 'new'
    end

    it 'stores the given values' do
      persistor.create_record(record_class, name: 'a', serialid: 100, status: 'x', created_at: time, token: uuid)
      persistor.flush

      expect(stored('a', :serialid, :status, :created_at, :token)).to eq [100, 'x', time, uuid]
    end

    it 'stores the values set by the block' do
      persistor.create_record(record_class, name: 'a') do |record|
        record.serialid = 100
        record.status = 'x'
      end
      persistor.flush

      expect(stored('a', :serialid, :status)).to eq [100, 'x']
    end

    it 'stores the database default for an empty string in a column with a computed default' do
      persistor.create_record(record_class, name: 'a', serialid: '')
      persistor.commit

      expect(stored('a', :serialid)).to be_present
    end

    unless except.include?(:nil_to_nil_update)
      it 'stores NULL for a computed column without a value set to nil by do_with_record' do
        persistor.create_record(record_class, name: 'a')
        persistor.do_with_record(record_class, {name: 'a'}) { |record| record.token = nil }
        persistor.commit

        expect(stored('a', :token)).to be_nil
      end
    end

    it 'stores the database default for an explicit nil in a column with a computed default' do
      persistor.create_record(record_class, name: 'a', token: nil)
      persistor.flush

      expect(stored('a', :token)).to be_present
    end

    it 'stores NULL for columns updated to nil' do
      persistor.create_record(record_class, name: 'a', status: 'x', token: uuid)
      persistor.create_record(record_class, name: 'b', status: 'x', token: uuid)
      persistor.update_all_records(record_class, {name: 'a'}, {status: nil, token: nil})
      persistor.do_with_record(record_class, {name: 'b'}) do |record|
        record.status = nil
        record.token = nil
      end
      persistor.flush

      expect(stored('a', :status, :token)).to eq [nil, nil]
      expect(stored('b', :status, :token)).to eq [nil, nil]
    end
  end

  context Sequent::Core::Persistors::ActiveRecordPersistor do
    let(:persistor) { Sequent::Core::Persistors::ActiveRecordPersistor.new }

    [true, false].each do |partial_inserts|
      context "with partial_inserts #{partial_inserts}" do
        before { record_class.partial_inserts = partial_inserts }

        context 'on a table' do
          let(:record_class) { PersistorDefaultsRecord }

          it_behaves_like 'a persistor storing columns without a value'
        end
      end
    end

    context 'on a view with partial_inserts true' do
      let(:record_class) { PersistorDefaultsViewRecord }

      before { record_class.partial_inserts = true }

      it_behaves_like 'a persistor storing columns without a value', except: [:explicit_nil]

      # ActiveRecord does not know the default of the column, so nil is not a change and the column is left out.
      it 'stores the database default for an explicit nil in a column with a constant default' do
        persistor.create_record(record_class, name: 'a', status: nil)
        persistor.flush

        expect(stored('a', :status)).to eq 'new'
      end
    end

    context 'on a view with partial_inserts false' do
      let(:record_class) { PersistorDefaultsViewRecord }

      before { record_class.partial_inserts = false }

      # ActiveRecord does not know the defaults of the columns, so it inserts NULL for all columns without a value
      # except the primary key.
      it 'stores NULL for the columns without a value' do
        persistor.create_record(record_class, name: 'a', serialid: 100, created_at: time)
        persistor.flush

        expect(stored('a', :id, :status, :token)).to match [be_present, nil, nil]
      end

      it 'fails for a NOT NULL column without a value' do
        expect { persistor.create_record(record_class, name: 'a') }.to raise_error(ActiveRecord::NotNullViolation)
      end
    end
  end

  context Sequent::Core::Persistors::ReplayOptimizedPostgresPersistor do
    let(:persistor) { Sequent::Core::Persistors::ReplayOptimizedPostgresPersistor.new }

    context 'on a table' do
      let(:record_class) { PersistorDefaultsRecord }

      it_behaves_like 'a persistor storing columns without a value', except: [:nil_to_nil_update]

      # Known difference: the record is not created yet, so the computed column has no value that is set to nil, and
      # the database still computes it. ActiveRecord inserts the computed value when creating the record, and stores
      # NULL when the record is updated.
      it 'stores the database default for a computed column without a value set to nil by do_with_record' do
        persistor.create_record(record_class, name: 'a')
        persistor.do_with_record(record_class, {name: 'a'}) { |record| record.token = nil }
        persistor.commit

        expect(stored('a', :token)).to be_present
      end
    end

    context 'on a view' do
      let(:record_class) { PersistorDefaultsViewRecord }

      it 'fails, since COPY does not support views' do
        persistor.create_record(record_class, name: 'a')

        expect { persistor.flush }.to raise_error(PG::WrongObjectType, /cannot copy to view/)
      end
    end
  end
end
