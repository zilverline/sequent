require 'spec_helper'
require 'timecop'
require 'active_support/hash_with_indifferent_access'
require_relative '../../../fixtures/db/1/classes'

describe Sequent::Migrations::ViewSchema do

  let(:view_schema) { 'test_view_schema' }
  let(:opts) { {db_config: db_config} }
  let(:migrator) { Sequent::Migrations::ViewSchema.new(opts) }
  let(:db_config) { ActiveSupport::HashWithIndifferentAccess.new(Database.test_config.merge(schema_search_path: "#{view_schema},public")).stringify_keys }

  before :each do
    Sequent.configure do |config|
      config.view_schema_name = view_schema
    end
    Sequent::Support::Database.disconnect!
    Sequent::Support::Database.establish_connection(db_config)
    exec_sql("drop schema if exists #{view_schema} cascade")
    exec_sql("drop table if exists #{Sequent.configuration.versions_table_name} cascade")
    exec_sql("delete from #{Sequent.configuration.event_record_class.table_name}")

    class SpecMigrations < Sequent::Migrations::Projectors
        def self.versions
          {
            '1' => [AccountProjector, MessageProjector]
          }
        end

        def self.version
          1
        end
      end
  end

  context '#create_view_schema_if_not_exists' do

    it 'creates the schema if not exists' do
      migrator.create_view_schema_if_not_exists

      expect(Sequent::ApplicationRecord.connection).to have_schema(view_schema)
    end

    it 'creates the migration table' do
      migrator.create_view_schema_if_not_exists

      expect(migrator.current_version).to eq 0
    end

    it 'does not fail when trying to create the schema again' do
      migrator.create_view_schema_if_not_exists
      migrator.create_view_schema_if_not_exists

      expect(Sequent::ApplicationRecord.connection).to have_schema(view_schema)
    end

  end

  context '#migrate_online' do
    let(:new_version) { SpecMigrations.version }

    before :each do
      AccountRecord.table_name = 'account_records'
      AccountRecord.reset_column_information
      MessageRecord.table_name = 'message_records'
      MessageRecord.reset_column_information

      Sequent.configure do |config|
        config.migration_sql_files_directory = 'spec/fixtures/db/1'
        config.migrations_class_name = 'SpecMigrations'
      end
    end

    context 'same version' do
      before do
        migrator.create_view_schema_if_not_exists
        Sequent::Migrations::ViewSchema::Versions.create!(version: new_version)
      end

      it 'does nothing if already on the correct version' do
        migrator.migrate_online

        expect(migrator.current_version).to eq new_version
      end
    end

    context 'lower version' do
      before do
        migrator.create_view_schema_if_not_exists
        Sequent::Migrations::ViewSchema::Versions.create!(version: 2)

        class SpecMigrations < Sequent::Migrations::Projectors
          def self.version
            1
          end
        end
      end

      it 'fails' do
        expect { migrator.migrate_online }.to raise_error ArgumentError
      end
    end

    context 'higher version' do
      before :each do
        migrator.create_view_schema_if_not_exists
        Sequent::Migrations::ViewSchema::Versions.create!(version: 0)
      end

      it 'creates the new view tables with the version as suffix' do
        migrator.migrate_online

        expect(Sequent::ApplicationRecord.connection).to have_view_schema_table('account_records_1')
        expect(Sequent::ApplicationRecord.connection).to have_view_schema_table('message_records_1')
      end

      it 'cleans old migration tables before migrating' do
        migrator.create_view_schema_if_not_exists

        exec_sql("create table #{view_schema}.account_records_0 (id serial)")
        exec_sql("create table #{view_schema}.account_records_1 (id serial)")

        migrator.migrate_online

        expect(Sequent::ApplicationRecord.connection).to_not have_view_schema_table('account_records_0')
        expect(Sequent::ApplicationRecord.connection).to have_view_schema_table('account_records_1')
      end

      it 'replays the data and keeps track of the migrated ids' do
        insert_events('Account', [AccountCreated.new(aggregate_id: Sequent.new_uuid, sequence_number: 1), AccountCreated.new(aggregate_id: Sequent.new_uuid, sequence_number: 1)])

        message_aggregate_id = Sequent.new_uuid
        insert_events('Message', [MessageCreated.new(aggregate_id: message_aggregate_id, sequence_number: 1), MessageSet.new(aggregate_id: message_aggregate_id, sequence_number: 2, message: 'Foobar')])

        migrator.migrate_online

        expect(AccountRecord.count).to eq 2
        expect(AccountRecord.table_name).to eq 'account_records_1'

        expect(MessageRecord.count).to eq 1
        expect(MessageRecord.table_name).to eq 'message_records_1'

        expect(Sequent::Migrations::ViewSchema::ReplayedIds.pluck(:event_id)).to match_array Sequent.configuration.event_record_class.pluck(:id)
      end

      context 'specific projectors' do
        before :each do
          class SpecMigrations < Sequent::Migrations::Projectors
            def self.versions
              {
                '1' => [AccountProjector]
              }
            end
          end
        end

        it 'only migrates the tables for the projector to migrate' do
          account_1 = Sequent.new_uuid
          account_2 = Sequent.new_uuid
          insert_events('Account', [AccountCreated.new(aggregate_id: account_1, sequence_number: 1), AccountCreated.new(aggregate_id: account_2, sequence_number: 1)])

          message_aggregate_id = Sequent.new_uuid
          insert_events('Message', [MessageCreated.new(aggregate_id: message_aggregate_id, sequence_number: 1), MessageSet.new(aggregate_id: message_aggregate_id, sequence_number: 2, message: 'Foobar')])

          migrator.migrate_online

          expect(AccountRecord.table_name).to eq 'account_records_1'
          expect(AccountRecord.count).to eq 2

          expect(MessageRecord.table_name).to eq 'message_records'
          expect(Sequent::ApplicationRecord.connection).to_not have_view_schema_table('message_records_1')

          expect(Sequent::Migrations::ViewSchema::ReplayedIds.pluck(:event_id)).to match_array Sequent.configuration.event_record_class.where(aggregate_id: [account_1, account_2]).pluck(:id)
        end
      end

    end

    context 'error handling' do
      before :each do
        migrator.create_view_schema_if_not_exists
        Sequent::Migrations::ViewSchema::Versions.create!(version: 0)
      end
      it 'stops and cleans up' do
        # force and error on replay by violating unique index in account_records
        account_id = Sequent.new_uuid
        insert_events('Account', [AccountCreated.new(aggregate_id: account_id, sequence_number: 1), AccountCreated.new(aggregate_id: account_id, sequence_number: 2)])

        expect { migrator.migrate_online }.to raise_error(Parallel::UndumpableException)

        expect(Sequent::ApplicationRecord.connection).to_not have_view_schema_table('account_records_1')
        expect(Sequent::Migrations::ViewSchema::ReplayedIds.count).to eq 0
      end
    end
  end

  context '#migrate_offline' do
    let(:new_version) { SpecMigrations.version }

    before :each do
      AccountRecord.table_name = 'account_records'
      AccountRecord.reset_column_information
      MessageRecord.table_name = 'message_records'
      MessageRecord.reset_column_information

      Sequent.configure do |config|
        config.migration_sql_files_directory = 'spec/fixtures/db/1'
        config.migrations_class_name = 'SpecMigrations'
      end
    end

    context 'same version' do
      before do
        migrator.create_view_schema_if_not_exists
        Sequent::Migrations::ViewSchema::Versions.create!(version: new_version)
      end

      it 'does nothing if already on the correct version' do
        migrator.migrate_offline

        expect(migrator.current_version).to eq new_version
      end
    end

    context 'lower version' do
      before do
        migrator.create_view_schema_if_not_exists
        Sequent::Migrations::ViewSchema::Versions.create!(version: 2)

        class SpecMigrations < Sequent::Migrations::Projectors
          def self.version
            1
          end
        end
      end

      it 'fails' do
        expect { migrator.migrate_offline }.to raise_error ArgumentError
      end
    end

    context 'higher version' do
      let(:account_id) { Sequent.new_uuid }
      let(:message_id) { Sequent.new_uuid }

      before :each do
        migrator.create_view_schema_if_not_exists
        Sequent::Migrations::ViewSchema::Versions.create!(version: 0)

        insert_events('Account', [AccountCreated.new(aggregate_id: account_id, sequence_number: 1)])
        insert_events('Message', [MessageCreated.new(aggregate_id: message_id, sequence_number: 1)])

        migrator.migrate_online

        expect(AccountRecord.count).to eq (1)
        expect(MessageRecord.count).to eq (1)
      end

      it 'replays events not yet replayed' do
        account_id_2 = Sequent.new_uuid
        account_id_3 = Sequent.new_uuid
        insert_events('Account', [AccountCreated.new(aggregate_id: account_id_2, sequence_number: 1), AccountCreated.new(aggregate_id: account_id_3, sequence_number: 1)])

        message_id_2 = Sequent.new_uuid
        insert_events('Message', [MessageCreated.new(aggregate_id: message_id_2, sequence_number: 1)])

        migrator.migrate_offline

        expect(AccountRecord.count).to eq (3)
        expect(AccountRecord.pluck(:aggregate_id)).to match_array [account_id, account_id_2, account_id_3]

        expect(MessageRecord.count).to eq (2)
        expect(MessageRecord.pluck(:aggregate_id)).to match_array [message_id, message_id_2]
      end

      it 'sets the new version' do
        migrator.migrate_offline

        expect(Sequent::Migrations::ViewSchema::Versions.maximum(:version)).to eq new_version
      end

      it 'ensures the "normal" table_names are set' do
        migrator.migrate_offline

        expect(AccountRecord.table_name).to eq 'account_records'
        expect(MessageRecord.table_name).to eq 'message_records'
      end

      context 'offline replaying with older events' do
        after :each do
          Timecop.return
        end

        it 'does not replay events older than 1 day' do
          Timecop.freeze(1.week.ago)

          old_account_id = Sequent.new_uuid
          old_account_created = AccountCreated.new(aggregate_id: old_account_id, sequence_number: 1)
          insert_events('Account', [old_account_created])

          Timecop.return

          new_account_id = Sequent.new_uuid
          new_account_created = AccountCreated.new(aggregate_id: new_account_id, sequence_number: 1)
          insert_events('Account', [new_account_created])

          migrator.migrate_offline

          expect(AccountRecord.pluck(:aggregate_id)).to_not include(old_account_id)
          expect(AccountRecord.pluck(:aggregate_id)).to include(new_account_id)
        end
      end
    end

    context 'error handling' do
      let(:account_id) { Sequent.new_uuid }

      before :each do
        migrator.create_view_schema_if_not_exists
        Sequent::Migrations::ViewSchema::Versions.create!(version: 0)
      end

      it 'fails when migrate_online was not called prior to migrate_offline' do
        expect { migrator.migrate_offline }.to raise_error Sequent::Migrations::MigrationError
      end

      it 'stops and does a rollback' do
        insert_events('Account', [AccountCreated.new(aggregate_id: account_id, sequence_number: 1)])
        migrator.migrate_online

        account_id_2 = Sequent.new_uuid
        # force and error on replay by violating unique index in account_records
        insert_events('Account', [AccountCreated.new(aggregate_id: account_id_2, sequence_number: 2), AccountCreated.new(aggregate_id: account_id_2, sequence_number: 3)])

        expect { migrator.migrate_offline }.to raise_error(Parallel::UndumpableException)

        expect(Sequent::ApplicationRecord.connection).to_not have_view_schema_table('message_records')
        expect(Sequent::ApplicationRecord.connection).to_not have_view_schema_table('account_records')
        expect(Sequent::Migrations::ViewSchema::ReplayedIds.count).to eq 0
      end

      context 'with an existing view schema' do
        let(:account_id) { Sequent.new_uuid }
        let(:message_id) { Sequent.new_uuid }

        before :each do
          insert_events('Account', [AccountCreated.new(aggregate_id: account_id, sequence_number: 1)])
          insert_events('Message', [MessageCreated.new(aggregate_id: message_id, sequence_number: 1)])

          migrator.migrate_online
          migrator.migrate_offline

          expect(AccountRecord.count).to eq (1)
          expect(MessageRecord.count).to eq (1)
        end

        it 'keeps the old state' do
          class SpecMigrations < Sequent::Migrations::Projectors
            def self.versions
              {
                '1' => [AccountProjector, MessageProjector],
                '2' => [AccountProjector, MessageProjector],
              }
            end

            def self.version
              2
            end
          end
          migrator.migrate_online

          expect(Sequent::ApplicationRecord.connection).to have_view_schema_table('message_records_2')
          expect(Sequent::ApplicationRecord.connection).to have_view_schema_table('account_records_2')

          account_id_2 = Sequent.new_uuid
          # force and error on replay by violating unique index in account_records
          insert_events('Account', [AccountCreated.new(aggregate_id: account_id_2, sequence_number: 2), AccountCreated.new(aggregate_id: account_id_2, sequence_number: 3)])

          expect { migrator.migrate_offline }.to raise_error(Parallel::UndumpableException)

          expect(Sequent::ApplicationRecord.connection).to_not have_view_schema_table('message_records_2')
          expect(Sequent::ApplicationRecord.connection).to_not have_view_schema_table('account_records_2')

          expect(Sequent::Migrations::ViewSchema::ReplayedIds.count).to eq 0
          expect(Sequent::Migrations::ViewSchema::Versions.maximum(:version)).to eq 1

          expect(AccountRecord.count).to eq (1)
          expect(MessageRecord.count).to eq (1)
          expect(AccountRecord.table_name).to eq 'account_records'
          expect(MessageRecord.table_name).to eq 'message_records'
        end
      end
    end
  end
end
