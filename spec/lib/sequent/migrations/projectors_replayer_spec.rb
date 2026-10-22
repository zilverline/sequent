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

  context 'extended statistics' do
    before do
      exec_update(<<~SQL)
        CREATE STATISTICS view_schema.single_records_base_table_stat (dependencies)
          ON aggregate_id, name FROM view_schema.single_records_base_table
      SQL
      exec_update('ALTER STATISTICS view_schema.single_records_base_table_stat SET STATISTICS 500')
      exec_update(<<~SQL)
        CREATE STATISTICS view_schema.single_records_p1_stat ON name, lower(name) FROM view_schema.single_records_p1
      SQL
      insert_events(5)
    end

    def replay!
      replayer = Sequent::Migrations::ProjectorsReplayer.create!(projector_classes:)
      replayer.prepare_for_replay
      replayer.perform_initial_replay
      replayer.prepare_for_activation!
      replayer.activate!
    end

    it 'copies them to the replay schema' do
      subject.prepare_for_replay

      expect(statistics_objects('replay_schema')).to contain_exactly(
        ['single_records_base_table_stat', 'replay_schema.single_records_base_table', 'f', 500, 'aggregate_id, name'],
        ['single_records_p1_stat', 'replay_schema.single_records_p1', 'dfme', -1, 'name, lower(name)'],
      )
    end

    it 'moves them along with the tables when activating' do
      replay!

      expect(statistics_objects('view_schema')).to contain_exactly(
        ['single_records_base_table_stat', 'view_schema.single_records_base_table', 'f', 500, 'aggregate_id, name'],
        ['single_records_p1_stat', 'view_schema.single_records_p1', 'dfme', -1, 'name, lower(name)'],
      )
      expect(statistics_objects('archive_schema')).to contain_exactly(
        ['single_records_base_table_stat', 'archive_schema.single_records_base_table', 'f', 500, 'aggregate_id, name'],
        ['single_records_p1_stat', 'archive_schema.single_records_p1', 'dfme', -1, 'name, lower(name)'],
      )
      expect(analyzed_statistics('view_schema')).to contain_exactly(
        'single_records_base_table_stat',
        'single_records_p1_stat',
      )
    end

    it 'keeps them over repeated replays' do
      replay!
      replay!

      expect(statistics_objects('view_schema').map(&:first)).to contain_exactly(
        'single_records_base_table_stat',
        'single_records_p1_stat',
      )
    end
  end

  context 'publications' do
    after do
      exec_update('DROP PUBLICATION IF EXISTS replayer_spec_publication')
    end

    it 'replays but refuses to activate when a publication lists a managed table by name' do
      exec_update('CREATE PUBLICATION replayer_spec_publication FOR TABLE view_schema.single_records_p1')
      insert_events(5)

      subject.prepare_for_replay
      subject.perform_initial_replay
      subject.prepare_for_activation!

      expect { subject.activate! }
        .to raise_error(/publication lists by name \(single_records_p1 in replayer_spec_publication\)/)
      expect(replay_state).to have_attributes(state: 'optimized')
    end

    it 'activates once the managed table is removed from the publication' do
      insert_events(5)
      subject.prepare_for_replay
      subject.perform_initial_replay
      subject.prepare_for_activation!

      exec_update('CREATE PUBLICATION replayer_spec_publication FOR TABLE view_schema.single_records_base_table')

      expect { subject.activate! }.to raise_error(/single_records_base_table in replayer_spec_publication/)
      expect(replay_state).to have_attributes(state: 'optimized')

      exec_update('DROP PUBLICATION replayer_spec_publication')
      subject.activate!

      expect(replay_state).to have_attributes(state: 'live')
    end

    it 'replays tables published through their schema' do
      exec_update('CREATE PUBLICATION replayer_spec_publication FOR TABLES IN SCHEMA view_schema')
      insert_events(5)

      subject.prepare_for_replay
      subject.perform_initial_replay
      subject.prepare_for_activation!
      subject.activate!

      expect(replay_state).to have_attributes(state: 'live')
    end
  end

  def statistics_objects(schema)
    exec_query(<<~SQL, [schema]).rows
      SELECT s.stxname, tn.nspname || '.' || t.relname, array_to_string(s.stxkind, ''), s.stxstattarget,
             pg_get_statisticsobjdef_columns(s.oid)
        FROM pg_statistic_ext s
        JOIN pg_namespace sn ON sn.oid = s.stxnamespace
        JOIN pg_class t ON t.oid = s.stxrelid
        JOIN pg_namespace tn ON tn.oid = t.relnamespace
       WHERE sn.nspname = $1
    SQL
  end

  def analyzed_statistics(schema)
    exec_query(<<~SQL, [schema]).rows.flatten.uniq
      SELECT statistics_name FROM pg_stats_ext WHERE statistics_schemaname = $1
    SQL
  end

  def record_count(schema) = select_value("SELECT COUNT(*) FROM #{schema}.single_records")

  def select_value(sql, binds = []) = ActiveRecord::Base.connection.select_value(sql, 'query', binds)
  def exec_query(sql, binds = []) = ActiveRecord::Base.connection.exec_query(sql, 'query', binds)
  def exec_update(sql, binds = []) = ActiveRecord::Base.connection.exec_update(sql, 'update', binds)
  def query_schemas = exec_query('SELECT nspname FROM pg_namespace').map { |r| r['nspname'] }

  def transaction(...) = Sequent.configuration.transaction_provider.transaction(...)

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
