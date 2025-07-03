# frozen_string_literal: true

require_relative 'event_replayer'

module Sequent
  module Migrations
    class ReplayState < ActiveRecord::Base
    end

    # Replay a set of projectors while the system is running and atomically replace the existing
    # tables with the replayed tables when completed.
    class ProjectorsReplayer
      include EventReplayer

      attr_reader :projector_classes, :managed_tables, :replay_schema_name

      def_delegators :connection, :exec_update, :exec_query, :quote_column_name, :quote_string, :quote_table_name

      def initialize(state:)
        super()

        @projector_classes = state.projectors.map { |p| Class.const_get(p) }
        if (unsupported = @projector_classes.reject { |p| p < Sequent::Core::Projector }).present?
          fail ArgumentError, "unsupported projectors #{unsupported.join(', ')}"
        end

        @state = state
        @managed_tables = projector_classes.flat_map(&:managed_tables)
        @replay_schema_name = "replay_schema_#{state.id}"
      end

      def self.create!(db_config:, projector_classes:)
        fail 'at least one projector must be specified' if projector_classes.empty?

        state = ReplayState.create!(state: 'created', projectors: projector_classes.map(&:name))
        new(db_config:, state:)
      end

      def self.resume_from_database(db_config:)
        state = ReplayState.where.not(state: 'done').last!
        new(db_config:, state:)
      end

      def prepare_for_replay
        @state.with_lock('FOR NO KEY UPDATE') do
          fail 'initial replay can only be performed when current state is `created`' unless @state.state == 'created'

          exec_update("CREATE SCHEMA #{@replay_schema_name}")
          @managed_tables.each do |table|
            exec_update(<<~SQL, 'create_table')
              CREATE TABLE #{replay_schema_name}.#{table.quoted_table_name} (LIKE #{view_schema_name}.#{table.quoted_table_name} INCLUDING ALL)
            SQL
          end

          @state.state = 'prepared'
          @state.save!
        end

        self
      end

      def perform_initial_replay
        maximum_xact_id_exclusive = @state.with_lock('FOR NO KEY UPDATE') do
          fail 'initial replay can only be performed when current state is `prepared`' unless @state.state == 'prepared'

          non_empty_tables = @managed_tables.select do |table|
            exec_query("SELECT 1 FROM #{quote_table_name(replay_schema_name)}.#{table.quoted_table_name} LIMIT 1")
              .to_a
              .present?
          end
          fail "managed tables #{non_empty_tables.join(', ')} are not empty" unless non_empty_tables.empty?

          @state.state = 'initial_replay'
          @state.save!

          Sequent::Support::Database.current_snapshot_xmin_xact_id
        end

        with_group = ->(group, index, &block) do
          logger.info("replaying #{index} group #{group}")

          Sequent::Support::Database.with_search_path(
            @replay_schema_name,
            Sequent.configuration.event_store_schema_name,
            &block
          )
        end

        replay!(
          Sequent.configuration.online_replay_persistor_class.new,
          projector_classes: @projector_classes,
          minimum_xact_id_inclusive: nil,
          maximum_xact_id_exclusive: maximum_xact_id_exclusive,
          with_group:,
        )

        @state.with_lock('FOR NO KEY UPDATE') do
          fail 'internal error' unless @state.state == 'initial_replay'

          @state.state = 'ready_for_activation'
          @state.continue_replay_at_xact_id = maximum_xact_id_exclusive
          @state.save!
        end
      end

      def done!
        transaction do
          @state = @state.lock!('FOR NO KEY UPDATE')
          @state.state = 'done'
          @state.save!

          exec_update("DROP SCHEMA #{quote_table_name(@replay_schema_name)} CASCADE")
        end
      end

      def view_schema_name = Sequent.configuration.view_schema_name

      def self.replay_projectors(db_config:, projectors:)
        fail 'projector_states must be enabled' unless Sequent.configuration.enable_projector_states

        # Create a new temporary table for each managed table using `CREATE TABLE foo_new (LIKE foo INCLUDING ALL)`
        # Update the table name for each managed table
        # Replay all events up to pg_current_snapshot()
        # ... can take a while so replay up-to new pg_current_snapshot()
        # Lock the projector_states table
        # Rename old tables to _old
        # Renam enew tables to update name
        # Release projector_states table lock

        if (unsupported = projectors.reject { |p| p < Sequent::Core::Projector }).present?
          fail ArgumentError, "unsupported projectors #{unsupported.join(', ')}"
        end

        view_schema = ViewSchema.new(db_config:)

        managed_tables = projectors.flat_map(&:managed_tables)

        maximum_xact_id_exclusive = exec_query(
          'SELECT pg_snapshot_xmin(pg_current_snapshot())::text::bigint',
          'pg_snapshot_xmin',
        )[0]['pg_snapshot_xmin']

        view_schema_name = Sequent.configuration.view_schema_name
        replay_schema_name = 'replay_schema'

        Sequent.configuration.transaction_provider.transactional do
          exec_update("CREATE SCHEMA IF NOT EXISTS #{replay_schema_name}")
          managed_tables.each do |table|
            exec_update(<<~SQL, 'create_table')
              CREATE TABLE #{replay_schema_name}.#{table.quoted_table_name} (LIKE #{view_schema_name}.#{table.quoted_table_name} INCLUDING ALL)
            SQL
          end
        end

        puts "initial replay of all events up-to xact id #{maximum_xact_id_exclusive}"
        view_schema.replay!(
          Sequent.configuration.online_replay_persistor_class.new,
          projectors:,
          maximum_xact_id_exclusive:,
          replay_schema_name:,
        )

        minimum_xact_id_inclusive = maximum_xact_id_exclusive
        maximum_xact_id_exclusive = exec_query(
          'SELECT pg_snapshot_xmin(pg_current_snapshot())::text::bigint',
          'pg_snapshot_xmin',
        )[0]['pg_snapshot_xmin']

        puts "replay events from #{minimum_xact_id_inclusive} up-to #{maximum_xact_id_exclusive}"
        view_schema.replay!(
          Sequent.configuration.offline_replay_persistor_class.new,
          projectors:,
          minimum_xact_id_inclusive:,
          maximum_xact_id_exclusive:,
          replay_schema_name:,
        )

        puts 'swapping managed tables to use replayed tables'
        Sequent.configuration.transaction_provider.transactional do
          Sequent::Core::Projectors.lock_projector_states_for_update

          ActiveRecord::Base.connection.exec_update(
            "SET LOCAL search_path TO #{replay_schema_name}, #{Sequent.configuration.event_store_schema_name}",
          )

          event_types = projectors.flat_map { |projector| projector.message_mapping.keys }.uniq.map(&:name)
          event_type_ids = Internal::EventType.where(type: event_types).pluck(:id)

          view_schema.replay_events(
            -> {
              view_schema.event_stream(nil..nil, event_type_ids, maximum_xact_id_exclusive, nil)
            },
            Sequent.configuration.offline_replay_persistor_class.new,
          ) { |progress| }

          managed_tables.each do |table|
            old_table_name = quote_table_name("#{table.table_name}_old")
            exec_update(<<~SQL, 'replace_table')
              DROP TABLE IF EXISTS #{old_table_name} CASCADE;
              ALTER TABLE #{view_schema_name}.#{table.quoted_table_name} RENAME TO #{old_table_name};
              ALTER TABLE #{replay_schema_name}.#{table.quoted_table_name} SET SCHEMA #{view_schema_name};
            SQL
          end
        end
      end

      def connection = ActiveRecord::Base.connection

      def transaction(...) = Sequent.configuration.transaction_provider.transactional(...)

      def transaction_in_replay_schema
        transaction do
          exec_update("SET search_path TO #{quote_table_name(replay_schema_name)}")
          yield
        end
      end

      def exec_update(...) = connection.exec_update(...)

      def exec_query(...) = connection.execute(...)

      def quote_table_name(...) = connection.quote_table_name(...)
    end
  end
end
