require 'spec_helper'
require 'sequent/support'
require 'tmpdir'

require_relative '../../migration_class'

class MockEvent < Sequent::Core::Event
  def initialize
    super(aggregate_id: 'foo', sequence_number: 1)
  end
end

describe Sequent::Core::Persistors::ReplayOptimizedPostgresPersistor do

  let(:persistor) { Sequent::Core::Persistors::ReplayOptimizedPostgresPersistor.new }
  let(:record_class) { Sequent::Core::EventRecord }
  let(:mock_event) { MockEvent.new }

  context '#get_record!' do
    it 'fails when no object is found' do
      expect { persistor.get_record!(record_class, {id: 1}) }.to raise_error(/record #{record_class} not found}*/)
    end
  end

  context '#update_record' do
    it 'fails when no object is found' do
      expect { persistor.update_record(record_class, mock_event, {id: 1}) }.to raise_error(/record #{record_class} not found}*/)
    end
  end

  context '#get_record' do
    it 'returns nil when no object is found' do
      expect(persistor.get_record(record_class, {id: 1})).to be_nil
    end
  end

  context '#find_records' do
    it 'returns empty array when no objects are found' do
      expect(persistor.find_records(record_class, {id: 1})).to be_empty
    end
  end

  context '#delete_all_records' do
    it 'does not fail when there is nothing to delete' do
      persistor.delete_all_records(record_class, {id: 1})
    end
  end

  context '#delete_record' do
    it 'does not fail when there is nothing to delete' do
      persistor.delete_record(record_class, record_class.new(id: 1))
    end
  end

  context '#update_all_records' do
    it 'does not fail when there is nothing to update' do
      persistor.update_all_records(record_class, {id: 1}, {sequence_number: 2})
    end
  end

  it 'can save multiple objects at once' do
    persistor.create_records(Sequent::Core::EventRecord, [{id: 1}, {id: 2}])
    object = persistor.get_record!(record_class, {id: 1})
    expect(object.id).to eq 1
    object = persistor.get_record!(record_class, {id: 2})
    expect(object.id).to eq 2
  end

  context 'with an object' do
    before :each do
      persistor.create_record(Sequent::Core::EventRecord, {id: 1})
    end

    context '#get_record!' do
      it 'returns the object' do
        object = persistor.get_record!(record_class, {id: 1})
        expect(object.id).to eq 1
      end

      context '#get_record' do
        it 'returns the object' do
          object = persistor.get_record(record_class, {id: 1})
          expect(object.id).to eq 1
        end
      end

      context '#find_records' do
        it 'returns the object' do
          objects = persistor.find_records(record_class, {id: 1})
          expect(objects).to have(1).item
          expect(objects.first.id).to eq 1
        end
      end

      context '#delete_all_records' do
        it 'deletes the object' do
          persistor.delete_all_records(record_class, {id: 1})

          objects = persistor.find_records(record_class, {id: 1})
          expect(objects).to be_empty
        end
      end

      context '#delete_record' do
        it 'deletes the object' do
          objects = persistor.find_records(record_class, {id: 1})
          persistor.delete_record(record_class, objects.first)

          expect(persistor.find_records(record_class, {id: 1})).to be_empty
        end
      end

      context '#update_all_records' do
        it 'updates the records' do
          persistor.update_all_records(record_class, {id: 1}, {sequence_number: 3})

          objects = persistor.find_records(record_class, {id: 1})
          expect(objects).to have(1).item
          expect(objects.first.id).to eq 1
          expect(objects.first.sequence_number).to eq 3
        end
      end
    end
  end

  context 'indices' do
    let(:aggregate_id) { Sequent.new_uuid }
    before :each do
      persistor.create_record(Sequent::Core::EventRecord, {id: 1, command_record_id: 2})
      persistor.create_record(Sequent::Core::EventRecord, {id: 1, sequence_number: 2})
      persistor.create_record(Sequent::Core::EventRecord, {aggregate_id: aggregate_id, id: 2})
    end

    let(:persistor) { Sequent::Core::Persistors::ReplayOptimizedPostgresPersistor.new(50, {
      Sequent::Core::EventRecord => [[:id, :command_record_id], [:id, :sequence_number]]
    }) }
    let(:records) { persistor.find_records(record_class, where_clause) }

    context '#find_records' do
      context 'with arbitrary where clause' do
        let(:where_clause) { {id: 1, command_record_id: 2} }
        it 'returns the correct number records' do
          expect(records).to have(1).item
        end

        it 'returns the correct record' do
          expect(records.first.id).to eq 1
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
        expect(persistor.find_records(record_class, {id: 1})).to have(2).items

        persistor.delete_all_records(record_class, {id: 1})

        expect(persistor.find_records(record_class, {id: 1})).to be_empty
      end

      it 'deletes the object based on multiple columns' do
        expect(persistor.find_records(record_class, {id: 1, command_record_id: 2})).to have(1).item

        persistor.delete_all_records(record_class, {id: 1, command_record_id: 2})

        expect(persistor.find_records(record_class, {id: 1, command_record_id: 2})).to be_empty
        expect(persistor.find_records(record_class, {id: 1, sequence_number: 2})).to have(1).item
      end
    end

    context '#update_all_records' do
      it 'only updates the records adhering to the where clause' do
        persistor.update_all_records(record_class, {id: 1, sequence_number: 2}, {command_record_id: 10})

        object = persistor.get_record!(record_class, {id: 1, sequence_number: 2})
        expect(object.id).to eq 1
        expect(object.command_record_id).to eq 10
      end

      it 'can update an indexed column' do
        persistor.update_all_records(record_class, {id: 1, sequence_number: 2}, {sequence_number: 99})

        expect(persistor.get_record(record_class, {id: 1, sequence_number: 2})).to be_nil

        object = persistor.get_record!(record_class, {id: 1, sequence_number: 99})
        expect(object.id).to eq 1
        expect(object.sequence_number).to eq 99
      end
    end
  end

  context 'committing' do
    class ReplayOptimizedPostgresTest < Sequent::ApplicationRecord; end

    let(:migrations_path) { File.expand_path(database_name, Dir.tmpdir).tap { |dir| Dir.mkdir(dir) } }
    let(:database_name) { Sequent.new_uuid }
    let(:db_config) do
      {'adapter' => 'postgresql',
        'host' => 'localhost',
        'database' => database_name}
    end
    let(:database) { Sequent::Support::Database.new }
    let(:persistor) { Sequent::Core::Persistors::ReplayOptimizedPostgresPersistor.new(insert_csv_size) }

    before do
      Sequent::Support::Database.create!(db_config)
      Sequent::Support::Database.establish_connection(db_config)
    end

    after { Sequent::Support::Database.drop!(db_config) }

    before :each do
      File.open(File.expand_path("1_test_migration.rb", migrations_path), 'w') do |f|
        f.write <<EOF
class TestMigration < MigrationClass
  def change
    create_table "replay_optimized_postgres_tests", id: false do |t|
      t.string "name", null: false
      t.string "initials", default: [], array:true
      t.timestamp "created_at", null: false
      t.timestamp "updated_at", null: false
    end
  end
end
EOF
        f.flush
        database.migrate(migrations_path, verbose: false)
      end
    end

    context 'csv' do
      let(:insert_csv_size) { 0 }
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

    context 'batch inserts' do
      let(:insert_csv_size) { 1 }
      let(:values) { {name: 'ben', initials: ['b'], created_at: DateTime.now} }

      context 'values as with_indifferent_access' do
        it 'commits a persistor' do
          persistor.create_record(ReplayOptimizedPostgresTest, values.with_indifferent_access)

          expect { persistor.commit }.to change { ReplayOptimizedPostgresTest.count }.by(1)
        end
      end

      context 'values as normal hashess' do
        it 'commits a persistor' do
          persistor.create_record(ReplayOptimizedPostgresTest, values)

          expect { persistor.commit }.to change { ReplayOptimizedPostgresTest.count }.by(1)
        end
      end
    end
  end
end
