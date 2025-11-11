# frozen_string_literal: true

require 'spec_helper'
require 'active_support/hash_with_indifferent_access'
require_relative '../fixtures/spec_migrations'

describe Sequent::Migrations::ProjectorsReplayer do
  before :each do
    SpecMigrations.reset
    Sequent::Migrations::ReplayState.delete_all
    Sequent::Core::ProjectorState.delete_all

    Sequent.configuration.event_handlers = [SingleRecordProjector.new]
    Sequent.configuration.enable_projector_states = true
    Sequent.configuration.event_publisher = Sequent::Core::ActiveProjectorsEventPublisher.new
    Sequent.configuration.migrations_class = SpecMigrations
    SpecMigrations.version = 0
    Sequent.activate_current_configuration!

    exec_update('DROP SCHEMA IF EXISTS archive_schema, replay_schema CASCADE')
    exec_update('DROP TABLE IF EXISTS view_schema.single_records')
    exec_update(<<~SQL)
      CREATE TABLE view_schema.single_records_base_table (
        aggregate_id uuid NOT NULL PRIMARY KEY,
        serialid bigserial NOT NULL,
        name text NOT NULL
      ) PARTITION BY HASH (aggregate_id)
    SQL
    exec_update(<<~SQL)
      CREATE TABLE view_schema.single_records_p1 PARTITION OF view_schema.single_records_base_table
         FOR VALUES WITH (MODULUS 2, REMAINDER 0)
    SQL
    exec_update(<<~SQL)
      CREATE TABLE view_schema.single_records_p2 PARTITION OF view_schema.single_records_base_table
         FOR VALUES WITH (MODULUS 2, REMAINDER 1)
    SQL
    # Reference the partitioned table through a view to see if replaying creates and restores all
    # tables/view correctly. Views are useful in the view schema to allow for zero-downtime
    # refactorings (e.g. renaming a column and using a view to have both names for the same columns
    # temporarily).
    exec_update(<<~SQL)
      CREATE VIEW view_schema.single_records AS SELECT * FROM view_schema.single_records_base_table
    SQL
  end
  after do
    Sequent::Migrations::ReplayState.delete_all
    exec_update('DROP SCHEMA IF EXISTS archive_schema, replay_schema CASCADE')
    exec_update('DROP TABLE IF EXISTS view_schema.single_records_base_table CASCADE')
    SpecMigrations.reset
    Sequent::Configuration.reset
  end

  class DummyCommand < Sequent::Core::BaseCommand; end
  class ProjectorsReplayEvent1 < Sequent::Core::Event
    attrs name: String
  end

  class ProjectorsReplayEvent2 < Sequent::Core::Event
    attrs name: String
  end

  class ProjectorsReplayTestAggregate < Sequent::Core::AggregateRoot
    attr_reader :name

    def events_partition_key = name[0..2]

    def initialize(aggregate_id:, name:)
      super(aggregate_id)
      apply ProjectorsReplayEvent1, name:
    end

    on ProjectorsReplayEvent1 do |event|
      @name = event.name
    end
  end

  class SingleRecord < ActiveRecord::Base
  end

  class SingleRecordProjector < Sequent::Core::Projector
    manages_tables SingleRecord

    on ProjectorsReplayEvent1 do |event|
      create_record(SingleRecord, {aggregate_id: event.aggregate_id, name: event.name})
    end
  end

  let(:projector_classes) { [SingleRecordProjector] }

  subject { Sequent::Migrations::ProjectorsReplayer.create!(projector_classes:) }

  def replay_state = Sequent::Migrations::ReplayState.last

  def insert_events(count)
    transaction do
      count.times do |i|
        Sequent.aggregate_repository.add_aggregate ProjectorsReplayTestAggregate.new(
          aggregate_id: Sequent.new_uuid,
          name: "#{i} aggregate",
        )
      end
      Sequent.aggregate_repository.commit(DummyCommand.new)
    end
  end

  context '#prepare_for_replay' do
    before do
      subject.prepare_for_replay
    end

    it 'should create a replay schema containing empty tables' do
      expect(replay_state).to have_attributes(state: 'prepared')

      expect(query_schemas).to include('replay_schema')

      expect(table_names('replay_schema')).to contain_exactly(
        'single_records',
        'single_records_base_table',
        'single_records_p1',
        'single_records_p2',
      )
    end

    it 'should fail if already prepared' do
      expect do
        subject.prepare_for_replay
      end.to raise_error(/when current state is created/)
    end
  end

  context '#abort!' do
    before do
      subject.prepare_for_replay
      subject.abort!
    end

    it 'should remove the replay schema name' do
      expect(query_schemas).to_not include('replay_schema')
      expect(Sequent::Migrations::ReplayState.last).to have_attributes(state: 'aborted')
    end

    it 'should allow preparing for replay again' do
      old_replay_state = Sequent::Migrations::ReplayState.last

      replayer = Sequent::Migrations::ProjectorsReplayer.create!(projector_classes: [SingleRecordProjector])
      replayer.prepare_for_replay

      new_replay_state = Sequent::Migrations::ReplayState.last
      expect(old_replay_state.id).to_not eq(new_replay_state.id)
    end
  end

  context '#initial_replay' do
    let(:initial_event_count) { 1000 }

    before do
      insert_events(initial_event_count)

      subject.prepare_for_replay
    end

    it 'should fail if the state is not `prepared`' do
      subject.abort!

      expect { subject.perform_initial_replay }
        .to raise_error(/initial replay can only be performed when current state is prepared/)
    end

    it 'should ensure the replay tables are empty for the initial replay' do
      in_replay_schema do
        SingleRecord.create!(aggregate_id: Sequent.new_uuid, name: 'name')
      end

      expect { subject.perform_initial_replay }.to raise_error(/not empty/)
    end

    context 'after initial replay is performed' do
      before do
        subject.perform_initial_replay
      end

      it 'should have replayed to the replay schema table' do
        expect(record_count('replay_schema')).to eq(initial_event_count)
      end

      it 'should not affect the view schema tables' do
        expect(record_count('view_schema')).to eq(initial_event_count)
      end

      it 'should be ready for incremental replay and or preparing for activation' do
        expect(replay_state).to have_attributes(state: 'replayed')
      end

      context '#incremental_replay' do
        let(:incremental_event_count) { 800 }

        before do
          insert_events(incremental_event_count)
          subject.perform_incremental_replay
        end

        it 'only processes the new events' do
          expect(record_count('replay_schema')).to eq(initial_event_count + incremental_event_count)
        end

        it 'can be executed multiple times' do
          extra_event_count = incremental_event_count / 10

          insert_events(extra_event_count)
          subject.perform_incremental_replay

          expect(record_count('replay_schema'))
            .to eq(initial_event_count + incremental_event_count + extra_event_count)
        end

        it 'can be executed without any more pending events' do
          subject.perform_incremental_replay

          expect(record_count('replay_schema')).to eq(initial_event_count + incremental_event_count)
        end

        it 'can be executed after preparing for activation' do
          subject.prepare_for_activation!

          subject.perform_incremental_replay
        end
      end
    end
  end

  context '#activate!' do
    before { subject.prepare_for_replay }

    it 'requires initial replay to have been completed' do
      expect { subject.activate! }
        .to raise_error(/going live can only be performed when current state is optimized/)
    end

    context 'when ready for activation' do
      let(:initial_event_count) { 5 }

      before do
        insert_events(initial_event_count)
        subject.perform_initial_replay
        subject.prepare_for_activation!
      end

      context 'with dependent objects' do
        before do
          exec_update('CREATE VIEW dependent AS SELECT * FROM view_schema.single_records')
        end

        it 'fails to activate if archived tables still have dependents' do
          expect { subject.activate! }.to raise_error(/other objects depend on it/)
        end

        it 'runs the after activate hook to allow for dependent objects to be re-created using the replayed tables' do
          Sequent.configuration.projectors_replayer_after_activate_hook = -> do
            exec_update('CREATE OR REPLACE VIEW dependent AS SELECT * FROM view_schema.single_records')
          end

          subject.activate!
        end
      end

      it 'incrementally replays the events within the transaction' do
        insert_events(10)

        subject.activate!

        expect(Sequent::Migrations::ReplayState.last).to have_attributes(state: 'live')
        expect(record_count('view_schema')).to eq(initial_event_count + 10)
        expect(record_count('archive_schema')).to eq(initial_event_count + 10)
      end

      it 'blocks projectors during activation so no events are missed or duplicated' do
        insert_events(1000)

        queue = Queue.new

        t = Thread.new do
          queue << 'starting'
          10.times do
            insert_events(100)
            sleep 0.01
          end
        end

        queue.deq

        sleep 0.05
        subject.activate!

        t.join

        expect(Sequent::Migrations::ReplayState.last).to have_attributes(state: 'live')
        expect(record_count('view_schema')).to eq(initial_event_count + 2000)
      end

      it 'renames the old table and replaces it with the new table' do
        subject.activate!

        expect(record_count('view_schema')).to eq(initial_event_count)
        tables = exec_query('SELECT tablename FROM pg_tables WHERE schemaname = $1', ['replay_schema']).to_a
        expect(tables).to be_empty
      end
    end
  end

  context 'schema changes' do
    it 'should allow modifying the replay schema before initial replay' do
      Sequent.configuration.projectors_replayer_after_prepare_hook = -> do
        exec_update('ALTER TABLE replay_schema.single_records_p1 RENAME TO single_records_even')
        exec_update('ALTER TABLE replay_schema.single_records_p2 RENAME TO single_records_odd')
      end

      subject.prepare_for_replay

      expect(table_names('replay_schema')).to contain_exactly(
        'single_records',
        'single_records_base_table',
        'single_records_even',
        'single_records_odd',
      )

      subject.perform_initial_replay
      subject.prepare_for_activation!
      subject.activate!

      expect(table_names('view_schema')).to include(
        'single_records',
        'single_records_base_table',
        'single_records_even',
        'single_records_odd',
      )
    end
  end

  def record_count(schema) = select_value("SELECT COUNT(*) FROM #{schema}.single_records")

  def select_value(sql, binds = []) = ActiveRecord::Base.connection.select_value(sql, 'query', binds)
  def exec_query(sql, binds = []) = ActiveRecord::Base.connection.exec_query(sql, 'query', binds)
  def exec_update(sql, binds = []) = ActiveRecord::Base.connection.exec_update(sql, 'update', binds)
  def query_schemas = exec_query('SELECT nspname FROM pg_namespace').map { |r| r['nspname'] }

  def transaction(...) = Sequent.configuration.transaction_provider.transactional(...)

  def in_replay_schema
    transaction do
      exec_update('SET LOCAL search_path TO replay_schema')
      yield
    end
  end

  def table_names(schema)
    exec_query(
      'SELECT table_name FROM information_schema.tables WHERE table_schema = $1',
      [schema],
    ).to_a.flat_map(&:values)
  end
end
