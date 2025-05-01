# frozen_string_literal: true

require 'spec_helper'
require 'active_support/hash_with_indifferent_access'
require_relative '../fixtures/spec_migrations'

describe Sequent::Migrations::ViewSchema do
  wait_for_persisted_events_to_become_visible_for_online_migration = -> do
    query = <<~EOS
      SELECT max(xact_id) IS NULL OR
             max(xact_id) < pg_snapshot_xmin(pg_current_snapshot())::text::bigint AS done
        FROM event_records
    EOS
    until ActiveRecord::Base.connection.exec_query(query).first['done']
      Sequent.logger.info 'Waiting for transactions to finish so test events are visible for online migration'
    end
  end

  let(:opts) { {db_config: db_config} }
  let(:migrator) { Sequent::Migrations::ViewSchema.new(**opts) }
  let(:database_name) { Sequent.new_uuid }
  let(:db_config) do
    Database.test_config.merge(
      'database' => database_name,
    )
  end
  before(:each) do
    @original_config = Sequent.configuration.database_config_directory
    Sequent.configuration.database_config_directory = "tmp/view_schema_spec/#{database_name}"
    Database.write_database_yml_for_test(env: 'test', database_name: database_name)
  end

  after(:each) do
    FileUtils.rm_rf('tmp/view_schema_spec')

    Sequent.configuration.database_config_directory = @original_config
  end

  before do
    Sequent::Support::Database.create!(db_config)
    ActiveRecord::Base.establish_connection(db_config)
  end
  after do
    Sequent::Support::Database.drop!(db_config)
    Sequent::Support::Database.disconnect!
  end

  let(:view_schema) { Sequent.configuration.view_schema_name }
  before :each do
    SpecMigrations.reset
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

    it 'can not insert two versions with a status' do
      migrator.create_view_schema_if_not_exists
      migrator.create_view_schema_if_not_exists

      Sequent::Migrations::Versions.create!(version: 1, status: nil)
      Sequent::Migrations::Versions.create!(version: 2, status: 1)
      expect do
        Sequent::Migrations::Versions.create!(version: 3, status: 2)
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  context '#create_view_tables' do
    before do
      Sequent.configure do |config|
        config.migration_sql_files_directory = 'spec/fixtures/db/1'
        config.migrations_class = SpecMigrations
        config.event_handlers = [
          AccountProjector,
          MessageProjector,
        ].map(&:new)
      end

      migrator.create_view_schema_if_not_exists
    end

    it 'creates everything' do
      migrator.create_view_tables

      expect(Sequent::ApplicationRecord.connection).to have_view_schema_table('account_records')
      expect(Sequent::ApplicationRecord.connection).to have_view_schema_table('message_records')
      expect(Sequent::ApplicationRecord.connection).to have_view_schema_index('message_records.message_records_message')
    end
  end

  context '#migrate_online' do
    let(:new_version) { SpecMigrations.version }

    before :each do
      Sequent::Migrations::SequentSchema.create_sequent_schema_if_not_exists(env: 'test')

      AccountRecord.table_name = 'account_records'
      AccountRecord.reset_column_information
      MessageRecord.table_name = 'message_records'
      MessageRecord.reset_column_information

      Sequent.configure do |config|
        config.migration_sql_files_directory = 'spec/fixtures/db/1'
        config.migrations_class = SpecMigrations
      end
    end

    context 'same version' do
      before do
        migrator.create_view_schema_if_not_exists
        Sequent::Migrations::Versions.create!(version: new_version)
      end

      it 'does nothing if already on the correct version' do
        migrator.migrate_online

        expect(migrator.current_version).to eq new_version
      end
    end

    context 'lower version' do
      before do
        migrator.create_view_schema_if_not_exists
        Sequent::Migrations::Versions.create!(version: 2)
        SpecMigrations.version = 1
      end

      it 'fails' do
        expect { migrator.migrate_online }.to raise_error ArgumentError
      end
    end

    context 'higher version' do
      before :each do
        migrator.create_view_schema_if_not_exists
        Sequent::Migrations::Versions.create!(version: 0)
      end

      it 'creates the new view tables with the version as suffix' do
        migrator.migrate_online

        expect(Sequent::ApplicationRecord.connection).to have_view_schema_table('account_records_1')
        expect(Sequent::ApplicationRecord.connection).to have_view_schema_table('message_records_1')
        expect(
          Sequent::ApplicationRecord.connection,
        ).to have_view_schema_index('message_records_1.message_records_message_1')
      end

      it 'cleans old migration tables before migrating' do
        migrator.create_view_schema_if_not_exists

        exec_sql("create table #{view_schema}.account_records_0 (id serial)")
        exec_sql("create table #{view_schema}.account_records_1 (id serial)")

        migrator.migrate_online

        expect(Sequent::ApplicationRecord.connection).to_not have_view_schema_table('account_records_0')
        expect(Sequent::ApplicationRecord.connection).to have_view_schema_table('account_records_1')
      end

      it 'replays the data and keeps track of the lowest transaction id of the currently in-progress transactions' do
        insert_events(
          'Account',
          [
            AccountCreated.new(aggregate_id: Sequent.new_uuid, sequence_number: 1),
            AccountCreated.new(aggregate_id: Sequent.new_uuid, sequence_number: 1),
          ],
          events_partition_key: 'a',
        )

        message_aggregate_id = Sequent.new_uuid
        insert_events(
          'Message',
          [
            MessageCreated.new(aggregate_id: message_aggregate_id, sequence_number: 1),
            MessageSet.new(aggregate_id: message_aggregate_id, sequence_number: 2, message: 'Foobar'),
          ],
          events_partition_key: 'b',
        )
        wait_for_persisted_events_to_become_visible_for_online_migration[]

        before_migration_xact_id = Sequent::Migrations::Versions.current_snapshot_xmin_xact_id

        migrator.migrate_online

        after_migration_xact_id = Sequent::Migrations::Versions.current_snapshot_xmin_xact_id

        expect(AccountRecord.table_name).to eq 'account_records'
        expect(AccountRecord.connection.select_value('select count(*) from account_records_1')).to eq 2

        expect(MessageRecord.table_name).to eq 'message_records'
        expect(AccountRecord.connection.select_value('select count(*) from message_records_1')).to eq 1

        expect(Sequent::Migrations::Versions.running.first.xmin_xact_id)
          .to (be > before_migration_xact_id).and(be < after_migration_xact_id)
      end

      context 'specific projectors' do
        before :each do
          SpecMigrations.versions = {
            '1' => [AccountProjector],
          }
        end

        it 'only migrates the tables for the projector to migrate' do
          account_1 = Sequent.new_uuid
          account_2 = Sequent.new_uuid
          insert_events(
            'Account',
            [
              AccountCreated.new(aggregate_id: account_1, sequence_number: 1),
              AccountCreated.new(aggregate_id: account_2, sequence_number: 1),
            ],
          )

          message_aggregate_id = Sequent.new_uuid
          insert_events(
            'Message',
            [
              MessageCreated.new(aggregate_id: message_aggregate_id, sequence_number: 1),
              MessageSet.new(aggregate_id: message_aggregate_id, sequence_number: 2, message: 'Foobar'),
            ],
          )
          wait_for_persisted_events_to_become_visible_for_online_migration[]

          migrator.migrate_online

          expect(AccountRecord.table_name).to eq 'account_records'
          expect(AccountRecord.connection.select_value('select count(*) from account_records_1')).to eq 2

          expect(MessageRecord.table_name).to eq 'message_records'
          expect(Sequent::ApplicationRecord.connection).to_not have_view_schema_table('message_records_1')
        end
      end

      context 'only alter_tables' do
        before do
          Sequent.configuration.migration_sql_files_directory = 'spec/fixtures/db/1'
          migrator.migrate_online # to version 1
          migrator.migrate_offline # to version 1
        end

        let(:new_migrator) { Sequent::Migrations::ViewSchema.new(**opts) }

        it 'does not replay with only alter tables' do
          Sequent.configuration.migration_sql_files_directory = 'spec/fixtures/db/2'
          SpecMigrations.copy_and_add('2', [Sequent::Migrations.alter_table(AccountRecord)])
          SpecMigrations.version = 2

          expect(new_migrator).to_not receive(:replay!)

          new_migrator.migrate_online
        end
      end
    end

    context 'error handling' do
      before :each do
        migrator.create_view_schema_if_not_exists
        Sequent::Migrations::Versions.create!(version: 0)
      end

      it 'stops and cleans up' do
        # force and error on replay by violating unique index in account_records
        account_id = Sequent.new_uuid
        insert_events(
          'Account',
          [
            AccountCreated.new(aggregate_id: account_id, sequence_number: 1),
            AccountCreated.new(aggregate_id: account_id, sequence_number: 2),
          ],
        )
        wait_for_persisted_events_to_become_visible_for_online_migration[]

        expect { migrator.migrate_online }.to raise_error(Parallel::UndumpableException)

        expect(Sequent::ApplicationRecord.connection).to_not have_view_schema_table('account_records_1')
        expect(Sequent::Migrations::Versions.count).to eq 1
        expect(Sequent::Migrations::Versions.first.version).to eq 0
      end

      context 'trying to start a migration when one is already started' do
        before do
          migrator.create_view_schema_if_not_exists
        end

        it 'will fail the newly started migration' do
          insert_events(
            'Account',
            [
              AccountCreated.new(aggregate_id: Sequent.new_uuid, sequence_number: 1),
              AccountCreated.new(aggregate_id: Sequent.new_uuid, sequence_number: 1),
            ],
          )
          wait_for_persisted_events_to_become_visible_for_online_migration[]

          result = Parallel.map([1, 2], in_processes: 2) do |_id|
            @connected ||= Sequent::Support::Database.establish_connection(db_config)
            migrator.migrate_online
            true
          rescue Sequent::Migrations::ConcurrentMigration
            false
          end
          Sequent::Support::Database.establish_connection(db_config)

          # Check that running migration is inserted in versions table
          expect(result).to include(false)
          expect(result).to include(true)
          expect(result).to have(2).items
          expect(migrator.current_version).to eq(0)
          expect(Sequent::Migrations::Versions.running.first).to be
          expect(Sequent::Migrations::Versions.running.first.version).to eq new_version

          # does not rollback the running migration
          expect(AccountRecord.table_name).to eq 'account_records'
          expect(AccountRecord.connection.select_value('select count(*) from account_records_1')).to eq 2
        end
      end
    end

    context 'migration of metadata tables' do
      before do
        migrator.create_view_schema_if_not_exists
        Sequent::Migrations::Versions.create!(version: new_version)
        exec_sql("alter table #{Sequent::Migrations::Versions.table_name} drop column status ")
        Sequent::Migrations::Versions.reset_column_information
      end

      it 'migrates the metadata tables correctly' do
        migrator.migrate_online
        expect(migrator.current_version).to eq new_version
      end
    end
  end

  context '#migrate_offline' do
    let(:new_version) { SpecMigrations.version }
    let(:configure_sequent) do
      Sequent.configure do |config|
        config.migration_sql_files_directory = 'spec/fixtures/db/1'
        config.migrations_class = SpecMigrations
      end
    end
    before :each do
      Sequent::Migrations::SequentSchema.create_sequent_schema_if_not_exists(env: 'test')

      AccountRecord.table_name = 'account_records'
      AccountRecord.reset_column_information
      MessageRecord.table_name = 'message_records'
      MessageRecord.reset_column_information

      configure_sequent
    end

    context 'same version' do
      before do
        migrator.create_view_schema_if_not_exists
        Sequent::Migrations::Versions.create!(version: new_version)
      end

      it 'does nothing if already on the correct version' do
        migrator.migrate_offline

        expect(migrator.current_version).to eq new_version
      end
    end

    context 'lower version' do
      before do
        migrator.create_view_schema_if_not_exists
        Sequent::Migrations::Versions.create!(version: 2)
        SpecMigrations.version = 1
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
        Sequent::Migrations::Versions.create!(version: 0)

        insert_events('Account', [AccountCreated.new(aggregate_id: account_id, sequence_number: 1)])
        insert_events('Message', [MessageCreated.new(aggregate_id: message_id, sequence_number: 1)])
        wait_for_persisted_events_to_become_visible_for_online_migration[]

        Sequent.configure do |config|
          config.migration_sql_files_directory = 'spec/fixtures/db/1'
          config.migrations_class = SpecMigrations
        end

        migrator.migrate_online

        expect(AccountRecord.connection.select_value('select count(*) from account_records_1')).to eq(1)
        expect(MessageRecord.connection.select_value('select count(*) from message_records_1')).to eq(1)
      end

      it 'replays events not yet replayed' do
        account_id_2 = Sequent.new_uuid
        account_id_3 = Sequent.new_uuid
        insert_events(
          'Account',
          [
            AccountCreated.new(aggregate_id: account_id_2, sequence_number: 1),
            AccountCreated.new(aggregate_id: account_id_3, sequence_number: 1),
          ],
        )

        message_id_2 = Sequent.new_uuid
        insert_events('Message', [MessageCreated.new(aggregate_id: message_id_2, sequence_number: 1)])

        migrator.migrate_offline

        expect(AccountRecord.count).to eq(3)
        expect(AccountRecord.pluck(:aggregate_id)).to match_array [account_id, account_id_2, account_id_3]

        expect(MessageRecord.count).to eq(2)
        expect(MessageRecord.pluck(:aggregate_id)).to match_array [message_id, message_id_2]
      end

      it 'sets the new version' do
        migrator.migrate_offline

        expect(Sequent::Migrations::Versions.done.maximum(:version)).to eq new_version
      end

      it 'tracks the affected projectors and tables' do
        Sequent.configuration.event_handlers = [
          AccountProjector,
          FooProjector,
          MessageProjector,
        ].map(&:new)

        expect(Sequent::Core::Projectors.projector_states).to match(
          'AccountProjector' => have_attributes(replaying_version: 1),
          'MessageProjector' => have_attributes(replaying_version: 1),
        )
        migrator.migrate_offline

        expect(Sequent::Migrations::Versions.done.latest.target_projectors)
          .to eq([AccountProjector.name, MessageProjector.name])
        expect(Sequent::Migrations::Versions.done.latest.target_records).to eq []
        expect(Sequent::Core::Projectors.projector_states).to match(
          'AccountProjector' => have_attributes(active_version: 1),
          'FooProjector' => have_attributes(active_version: 1),
          'MessageProjector' => have_attributes(active_version: 1),
        )

        Sequent.configuration.migration_sql_files_directory = 'spec/fixtures/db/2'
        SpecMigrations.copy_and_add('2', [FooProjector, Sequent::Migrations.alter_table(AccountRecord)])
        SpecMigrations.version = 2

        new_migrator = Sequent::Migrations::ViewSchema.new(**opts)

        new_migrator.migrate_online
        expect(Sequent::Core::Projectors.projector_states).to match(
          'AccountProjector' => have_attributes(active_version: 1),
          'MessageProjector' => have_attributes(active_version: 1),
          'FooProjector' => have_attributes(active_version: 1, replaying_version: 2),
        )

        new_migrator.migrate_offline

        expect(Sequent::Migrations::Versions.done.latest.target_records).to eq ['AccountRecord']
        expect(Sequent::Core::Projectors.projector_states).to match(
          'AccountProjector' => have_attributes(active_version: 2),
          'MessageProjector' => have_attributes(active_version: 2),
          'FooProjector' => have_attributes(active_version: 2),
        )
      end

      it 'ensures the "normal" table_names are set' do
        migrator.migrate_offline

        expect(AccountRecord.table_name).to eq 'account_records'
        expect(MessageRecord.table_name).to eq 'message_records'
      end
    end

    context 'single table inheritance' do
      let(:configure_sequent) do
        SpecMigrations.copy_and_add('1', [FooProjector])
        Sequent.configure do |config|
          config.migration_sql_files_directory = 'spec/fixtures/db/1'
          config.migrations_class = SpecMigrations
          config.online_replay_persistor_class = Sequent::Core::Persistors::ReplayOptimizedPostgresPersistor
        end
      end
      let(:next_migration) { Sequent::Migrations::ViewSchema.new(**opts) }

      before :each do
        migrator.create_view_schema_if_not_exists
        Sequent::Migrations::Versions.create!(version: 0)

        insert_events('Message', [MessageCreated.new(aggregate_id: Sequent.new_uuid, sequence_number: 1)])
        wait_for_persisted_events_to_become_visible_for_online_migration[]

        migrator.migrate_online
        migrator.migrate_offline

        # call table_name on the subclass to mimic a more complex Plan
        expect(FooRecord.table_name).to eq BaseFooRecord.table_name

        SpecMigrations.copy_and_add('2', [FooProjector])
        SpecMigrations.version = 2
        Sequent.configuration.migration_sql_files_directory = 'spec/fixtures/db/2'

        next_migration.migrate_online
      end

      it 'works' do
        insert_events(
          'Message',
          [MessageWithAddedColumnCreated.new(aggregate_id: Sequent.new_uuid, sequence_number: 1)],
        )

        wait_for_persisted_events_to_become_visible_for_online_migration[]
        next_migration.migrate_offline

        expect(FooRecord.count).to eq(2)
      end
    end

    context 'error handling' do
      let(:account_id) { Sequent.new_uuid }

      before :each do
        migrator.create_view_schema_if_not_exists
        Sequent::Migrations::Versions.create!(version: 0)
      end

      it 'fails when migrate_online was not called prior to migrate_offline' do
        expect { migrator.migrate_offline }.to raise_error Sequent::Migrations::MigrationError
        expect(Sequent::Migrations::Versions.running.count).to eq 0
      end

      it 'stops and does a rollback' do
        insert_events('Account', [AccountCreated.new(aggregate_id: account_id, sequence_number: 1)])
        wait_for_persisted_events_to_become_visible_for_online_migration[]

        migrator.migrate_online

        account_id_2 = Sequent.new_uuid
        # force and error on replay by violating unique index in account_records
        insert_events(
          'Account',
          [
            AccountCreated.new(aggregate_id: account_id_2, sequence_number: 1),
            AccountCreated.new(aggregate_id: account_id_2, sequence_number: 2),
          ],
        )

        expect { migrator.migrate_offline }.to raise_error(Parallel::UndumpableException)

        expect(Sequent::ApplicationRecord.connection).to_not have_view_schema_table('message_records')
        expect(Sequent::ApplicationRecord.connection).to_not have_view_schema_table('account_records')
        expect(Sequent::Migrations::Versions.count).to eq 1
        expect(Sequent::Migrations::Versions.running.count).to eq 0
      end

      context 'with an existing view schema' do
        let(:account_id) { Sequent.new_uuid }
        let(:message_id) { Sequent.new_uuid }
        let(:next_migration) { Sequent::Migrations::ViewSchema.new(**opts) }

        before :each do
          insert_events('Account', [AccountCreated.new(aggregate_id: account_id, sequence_number: 1)])
          insert_events('Message', [MessageCreated.new(aggregate_id: message_id, sequence_number: 1)])
          wait_for_persisted_events_to_become_visible_for_online_migration[]

          migrator.migrate_online
          migrator.migrate_offline

          expect(AccountRecord.count).to eq(1)
          expect(MessageRecord.count).to eq(1)
        end

        it 'keeps the old state' do
          SpecMigrations.versions =
            {
              '1' => [AccountProjector, MessageProjector],
              '2' => [AccountProjector, MessageProjector],
            }
          SpecMigrations.version = 2
          pp Sequent::Core::Projectors.projector_states
          next_migration.migrate_online

          expect(Sequent::ApplicationRecord.connection).to have_view_schema_table('message_records_2')
          expect(Sequent::ApplicationRecord.connection).to have_view_schema_table('account_records_2')

          account_id_2 = Sequent.new_uuid
          # force and error on replay by violating unique index in account_records
          insert_events(
            'Account',
            [
              AccountCreated.new(aggregate_id: account_id_2, sequence_number: 1),
              AccountCreated.new(aggregate_id: account_id_2, sequence_number: 2),
            ],
          )

          expect { next_migration.migrate_offline }.to raise_error(Parallel::UndumpableException)

          expect(Sequent::ApplicationRecord.connection).to_not have_view_schema_table('message_records_2')
          expect(Sequent::ApplicationRecord.connection).to_not have_view_schema_table('account_records_2')

          expect(Sequent::Migrations::Versions.maximum(:version)).to eq 1

          expect(AccountRecord.count).to eq(1)
          expect(MessageRecord.count).to eq(1)
          expect(AccountRecord.table_name).to eq 'account_records'
          expect(MessageRecord.table_name).to eq 'message_records'
        end

        context 'calling migrate_offline more then once for the same migration' do
          before do
            SpecMigrations.versions =
              {
                '1' => [AccountProjector, MessageProjector],
                '2' => [AccountProjector, MessageProjector],
              }
            SpecMigrations.version = 2
            next_migration.migrate_online
            expect(Sequent::ApplicationRecord.connection).to have_view_schema_table('message_records_2')
            expect(Sequent::ApplicationRecord.connection).to have_view_schema_table('account_records_2')
          end

          it 'fails when started concurrently' do
            result = Parallel.map([1, 2], in_processes: 2) do |_id|
              @connected ||= Sequent::Support::Database.establish_connection(db_config)
              next_migration.migrate_offline
              true
            rescue Sequent::Migrations::ConcurrentMigration
              false
            end
            Sequent::Support::Database.establish_connection(db_config)

            # Check that running migration is inserted in versions table
            expect(result).to include(false)
            expect(result).to include(true)
            expect(result).to have(2).items
            expect(migrator.current_version).to eq(2)
            expect(Sequent::Migrations::Versions.done.first).to be
            expect(Sequent::Migrations::Versions.done.order('version desc').first.version).to eq new_version
          end

          it 'ignores when migration is done' do
            expect { next_migration.migrate_offline }.to change { next_migration.current_version }.from(1).to(2)
            expect { next_migration.migrate_offline }.to_not change { next_migration.current_version }
          end
        end

        context 'only alter_tables' do
          it 'only adds the colum to the table' do
            expect(AccountRecord).to_not have_column('foobar')

            Sequent.configuration.migration_sql_files_directory = 'spec/fixtures/db/2'
            SpecMigrations.copy_and_add('2', [Sequent::Migrations.alter_table(AccountRecord)])
            SpecMigrations.version = 2
            expect(next_migration).to_not receive(:replay!)
            next_migration.migrate_online

            next_migration.migrate_offline

            expect(AccountRecord).to have_column('foobar')
          end
        end

        it 'missing the correct alter table file' do
          expect(MessageRecord).to_not have_column('foobar')
          Sequent.configuration.migration_sql_files_directory = 'spec/fixtures/db/2'
          SpecMigrations.copy_and_add('3', [Sequent::Migrations.alter_table(MessageRecord)])
          SpecMigrations.version = 3
          expect(next_migration).to_not receive(:replay!)

          expect { next_migration.migrate_online }.to raise_error(Sequent::Migrations::InvalidMigrationDefinition)

          expect(Sequent::Migrations::Versions.where(version: 3).first).to be_nil
        end
      end
    end
  end
end
