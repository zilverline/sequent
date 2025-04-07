# frozen_string_literal: true

require 'spec_helper'

describe Sequent::Core::Projector do
  it 'fails when missing managed_tables' do
    class TestProjector1 < Sequent::Core::Projector
      self.skip_autoregister = true
    end

    expect do
      Sequent.configuration.event_handlers << TestProjector1.new
    end.to raise_error(/A Projector must manage at least one table/)
  end

  context 'given enable_offline_migration_read_only_mode set to true' do
    class Versions < Sequent::Migrations::Projectors
      def self.version
        1
      end
    end

    class MigrationTestRecord; end

    class MigrationTestEvent < Sequent::Core::Event; end

    class MigrationTestProjector < Sequent::Core::Projector
      manages_tables MigrationTestRecord

      on MigrationTestEvent do
      end
    end

    before do
      Sequent.configuration.migrations_class_name = Versions.name
      Sequent.configuration.enable_offline_migration_read_only_mode = true
    end

    subject(:handle_message) do
      MigrationTestProjector.new.handle_message(
        MigrationTestEvent.new(aggregate_id: Sequent.new_uuid, sequence_number: 1),
      )
    end

    context 'and no migration' do
      it 'succeeds' do
        expect { subject }.to_not raise_error
      end
    end

    context 'and a migration for projector' do
      before do
        Sequent::Migrations::Versions.create!(version: 2, status:, target_projectors: [MigrationTestProjector.name])
      end

      after do
        Sequent::Migrations::Versions.delete_all
      end

      context 'online migration' do
        context 'running' do
          let(:status) { Sequent::Migrations::Versions::MIGRATE_ONLINE_RUNNING }
          it 'succeeds' do
            expect { subject }.to_not raise_error
          end
        end

        context 'finished' do
          let(:status) { Sequent::Migrations::Versions::MIGRATE_ONLINE_FINISHED }
          it 'succeeds' do
            expect { subject }.to_not raise_error
          end
        end
      end

      context 'offline migration' do
        context 'running' do
          let(:status) { Sequent::Migrations::Versions::MIGRATE_OFFLINE_RUNNING }
          it 'raises ReadOnlyModeEnabled ' do
            expect { subject }.to raise_error(Sequent::Core::Projector::ReadOnlyModeEnabled)
          end
        end

        context 'finished' do
          let(:status) { Sequent::Migrations::Versions::DONE }
          it 'raises ReadOnlyModeEnabled' do
            expect { subject }.to raise_error(Sequent::Core::Projector::ReadOnlyModeEnabled)
          end
        end
      end
    end

    context 'and a migration for managed_table' do
      before do
        Sequent::Migrations::Versions.create!(version: 2, status:, target_records: [MigrationTestRecord.name])
      end

      after do
        Sequent::Migrations::Versions.delete_all
      end

      context 'offline migration' do
        context 'running' do
          let(:status) { Sequent::Migrations::Versions::MIGRATE_OFFLINE_RUNNING }
          it 'raises ReadOnlyModeEnabled ' do
            expect { subject }.to raise_error(Sequent::Core::Projector::ReadOnlyModeEnabled)
          end
        end
      end
    end
  end
end
