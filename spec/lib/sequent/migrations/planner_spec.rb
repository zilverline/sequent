require 'spec_helper'
require_relative '../fixtures/spec_migrations'

describe Sequent::Migrations::Planner do
  let(:planner) { Sequent::Migrations::Planner.new(versions) }
  let(:versions) { SpecMigrations.versions }
  before { SpecMigrations.reset }

  context 'Projectors' do
    before do
      SpecMigrations.copy_and_add('1', [AccountProjector])
    end

    it 'adds migrations for the table' do
      expect(planner.plan(0, 1).migrations).to eq [
        Sequent::Migrations::ReplayTable.create(AccountRecord, '1'),
      ]
    end

    context 'multiple projectors' do
      before do
        SpecMigrations.copy_and_add('1', [AccountProjector, MessageProjector])
      end

      it 'adds migrations for the tables' do
        expect(planner.plan(0, 1).migrations).to eq [
          Sequent::Migrations::ReplayTable.create(AccountRecord, '1'),
          Sequent::Migrations::ReplayTable.create(MessageRecord, '1'),
        ]
      end
    end

    context 'projector managing multiple tables' do
      before do
        SpecMigrations.copy_and_add('1', [ItemProjector])
      end

      it 'adds migrations for the tables' do
        expect(planner.plan(0, 1).migrations).to eq [
          Sequent::Migrations::ReplayTable.create(ItemRecord, '1'),
          Sequent::Migrations::ReplayTable.create(LineItemRecord, '1'),
        ]
      end
    end
  end

  context 'ReplayTable' do
    before do
      SpecMigrations.copy_and_add('1', [AccountProjector, MessageProjector])
    end

    context 'multiple redundancy' do
      before do
        SpecMigrations.copy_and_add('2', [AccountProjector, MessageProjector])
      end

      it 'removes redundant replays' do
        expect(planner.plan(0, 2).migrations).to eq [
          Sequent::Migrations::ReplayTable.create(AccountRecord, '2'),
          Sequent::Migrations::ReplayTable.create(MessageRecord, '2'),
        ]
      end
    end

    context 'single redundancy' do
      before do
        SpecMigrations.copy_and_add('2', [MessageProjector])
      end

      it 'removes redundant replays' do
        expect(planner.plan(0, 2).migrations).to eq [
          Sequent::Migrations::ReplayTable.create(AccountRecord, '1'),
          Sequent::Migrations::ReplayTable.create(MessageRecord, '2'),
        ]
      end
    end
  end

  context 'AlterTable' do
    let(:migration_sql_files_directory) { 'spec/fixtures/db/2' }
    before :each do
      Sequent.configure do |config|
        config.migration_sql_files_directory = migration_sql_files_directory
      end
    end

    context 'validation' do
      let(:migration_sql_files_directory) { 'db/tables' }

      before do
        SpecMigrations.copy_and_add('2', [Sequent::Migrations.alter_table(AccountRecord)])
      end

      it 'fails when defining an AlterTable without the corresponding sql file' do
        expect {
          planner.plan(0, 2)
        }.to raise_error %r{db/tables/account_records_2.sql to apply for version 2}
      end
    end

    context 'single alter table' do
      before :each do
        SpecMigrations.copy_and_add('2', [Sequent::Migrations.alter_table(AccountRecord)])
      end

      it 'creates a plan' do
        expect(planner.plan(1, 2).migrations).to eq [
          Sequent::Migrations::AlterTable.create(AccountRecord, '2'),
        ]
      end
    end

    context "multiple AlterTable's" do
      before :each do
        SpecMigrations.copy_and_add('2', [Sequent::Migrations.alter_table(AccountRecord)])
        SpecMigrations.copy_and_add('3', [Sequent::Migrations.alter_table(AccountRecord)])
      end

      it 'creates a plan' do
        expect(planner.plan(1, 3).migrations).to eq [
          Sequent::Migrations::AlterTable.create(AccountRecord, '2'),
          Sequent::Migrations::AlterTable.create(AccountRecord, '3'),
        ]
      end
    end

    context 'alter table with replay table' do

      before :each do
        SpecMigrations.copy_and_add('1', [AccountProjector])
        SpecMigrations.copy_and_add('2', [Sequent::Migrations.alter_table(AccountRecord)])
      end

      it 'plans both' do
        expect(planner.plan(0, 2).migrations).to eq [
          Sequent::Migrations::ReplayTable.create(AccountRecord, '1'),
          Sequent::Migrations::AlterTable.create(AccountRecord, '2'),
        ]
      end
    end
  end

  context 'Ordering' do
    let(:migration_sql_files_directory) { 'spec/fixtures/db/2' }

    before do
      Sequent.configure do |config|
        config.migration_sql_files_directory = migration_sql_files_directory
      end
    end

    context 'orders the migrations' do
      before do
        SpecMigrations.copy_and_add('1', [AccountProjector])
        SpecMigrations.copy_and_add('3', [
          MessageProjector,
          Sequent::Migrations.alter_table(AccountRecord)
        ])
        SpecMigrations.copy_and_add('2', [Sequent::Migrations.alter_table(AccountRecord)])
      end

      it 'by version' do
        expect(planner.plan(0, 3).migrations).to eq [
          Sequent::Migrations::ReplayTable.create(AccountRecord, '1'),
          Sequent::Migrations::AlterTable.create(AccountRecord, '2'),
          Sequent::Migrations::ReplayTable.create(MessageRecord, '3'),
          Sequent::Migrations::AlterTable.create(AccountRecord, '3')
        ]
      end
    end

    context 'AlterTable before ReplayTable' do
      before do
        SpecMigrations.copy_and_add('1', [AccountProjector])
        SpecMigrations.copy_and_add('2', [
          Sequent::Migrations.alter_table(AccountRecord),
          Sequent::Migrations.alter_table(MessageRecord),
        ])
        SpecMigrations.copy_and_add('3', [AccountProjector])
      end

      it "does not plan the AlterTable's" do
        expect(planner.plan(0, 3).migrations).to eq [
          Sequent::Migrations::AlterTable.create(MessageRecord, '2'),
          Sequent::Migrations::ReplayTable.create(AccountRecord, '3'),
        ]
      end
    end

    context 'multiple AlterTable before ReplayTable' do
      before do
        SpecMigrations.copy_and_add('2', [Sequent::Migrations.alter_table(AccountRecord)])
        SpecMigrations.copy_and_add('3', [Sequent::Migrations.alter_table(AccountRecord)])
        SpecMigrations.copy_and_add('4', [AccountProjector])
      end

      it "does not plan the AlterTable's" do
        expect(planner.plan(2, 4).migrations).to eq [
          Sequent::Migrations::ReplayTable.create(AccountRecord, '4'),
        ]
      end
    end
  end
end
