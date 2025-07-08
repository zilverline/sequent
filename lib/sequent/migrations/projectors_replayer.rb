# frozen_string_literal: true

require_relative 'event_replayer'
require 'active_support/core_ext/integer/inflections'

module Sequent
  module Migrations
    class ReplayState < ActiveRecord::Base
      scope :replaying, -> { where(state: %w[initial_replay incremental_replay]) }
    end

    # Replay a set of projectors while the system is running and atomically replace the existing
    # tables with the replayed tables when completed.
    class ProjectorsReplayer
      extend Forwardable
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
        @replay_schema_name = 'replay_schema'
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

          exec_update("CREATE SCHEMA IF NOT EXISTS #{replay_schema_name}")
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

      def perform_incremental_replay
        maximum_xact_id_exclusive = @state.with_lock('FOR NO KEY UPDATE') do
          unless @state.state == 'ready_for_activation'
            fail 'incremental replay can only be performed when current state is `ready_for_activation`'
          end

          @state.state = 'incremental_replay'
          @state.save!

          Sequent::Support::Database.current_snapshot_xmin_xact_id
        end

        replay!(
          Sequent.configuration.offline_replay_persistor_class.new,
          projector_classes: @projector_classes,
          minimum_xact_id_inclusive: @state.continue_replay_at_xact_id,
          maximum_xact_id_exclusive: maximum_xact_id_exclusive,
          with_group:,
        )

        @state.with_lock('FOR NO KEY UPDATE') do
          fail 'internal error' unless @state.state == 'incremental_replay'

          @state.state = 'ready_for_activation'
          @state.continue_replay_at_xact_id = maximum_xact_id_exclusive
          @state.save!
        end
      end

      def activate!
        @state.with_lock('FOR NO KEY UPDATE') do
          unless @state.state == 'ready_for_activation'
            fail 'activation can only be performed when current state is `ready_for_activation`'
          end

          Sequent::Core::Projectors.lock_projector_states_for_update

          event_types = projector_classes.flat_map { |p| p.message_mapping.keys }.uniq.map(&:name)
          event_type_ids = Internal::EventType.where(type: event_types).pluck(:id)

          Sequent::Support::Database.with_search_path(replay_schema_name, event_store_schema_name) do
            with_sequent_config(
              Sequent.configuration.offline_replay_persistor_class.new,
              @projector_classes,
            ) do
              replay_events(
                -> {
                  event_stream(nil..nil, event_type_ids, @state.continue_replay_at_xact_id, nil)
                },
                Sequent.configuration.offline_replay_persistor_class.new,
              ) { |progress| }
            end
          end

          exec_update("DROP SCHEMA IF EXISTS #{quoted_archive_schema_name} CASCADE")
          exec_update("CREATE SCHEMA #{quoted_archive_schema_name}")

          replace_replayed_tables_in_view_schema(managed_tables)

          @state.state = 'done'
          @state.save!
        end
      end

      def done!
        transaction do
          @state = @state.lock!('FOR NO KEY UPDATE')
          @state.state = 'done'
          @state.save!

          exec_update("DROP SCHEMA #{quoted_replay_schema_name} CASCADE")
        end
      end

      private

      def with_group
        ->(group, index, &block) do
          logger.info("replaying #{(index + 1).ordinalize} group [#{group}]")

          Sequent::Support::Database.with_search_path(
            replay_schema_name,
            event_store_schema_name,
            &block
          )
        end
      end

      def replace_replayed_tables_in_view_schema(tables)
        tables.each do |table|
          exec_update(<<~SQL, 'replace_table')
            ALTER TABLE IF EXISTS #{quoted_view_schema_name}.#{table.quoted_table_name} SET SCHEMA #{quoted_archive_schema_name};
            ALTER TABLE #{quoted_replay_schema_name}.#{table.quoted_table_name} SET SCHEMA #{quoted_view_schema_name};
          SQL

          # Migrate owned sequences to the new table
          owned_sequences = exec_query(<<~SQL, 'owned_sequences').to_a
            SELECT s.relname AS seq, a.attname AS col
              FROM pg_class s
              JOIN pg_depend d ON d.objid = s.oid AND d.classid = 'pg_class'::regclass AND d.refclassid = 'pg_class'::regclass
              JOIN pg_class t ON t.oid = d.refobjid
              JOIN pg_namespace n ON n.oid = t.relnamespace
              JOIN pg_attribute a ON a.attrelid=t.oid AND a.attnum = d.refobjsubid
             WHERE s.relkind = 'S'
               AND d.deptype = 'a'
               AND n.nspname = '#{quote_string(archive_schema_name)}'
               AND t.relname = '#{quote_string(table.table_name)}'
          SQL

          owned_sequences.each do |sequence|
            quoted_sequence_name = quote_table_name(sequence['seq'])
            exec_update(<<~SQL, 'alter_sequence_owned_by')
              ALTER SEQUENCE #{quoted_archive_schema_name}.#{quoted_sequence_name} OWNED BY NONE;
              ALTER SEQUENCE #{quoted_archive_schema_name}.#{quoted_sequence_name} SET SCHEMA #{quoted_view_schema_name};
              ALTER SEQUENCE #{quoted_view_schema_name}.#{quoted_sequence_name}
                    OWNED BY #{quoted_view_schema_name}.#{table.quoted_table_name}.#{quote_column_name(sequence['col'])};
            SQL
          end
        end
      end

      def archive_schema_name = 'archive_schema'
      def event_store_schema_name = Sequent.configuration.event_store_schema_name
      def view_schema_name = Sequent.configuration.view_schema_name

      def quoted_archive_schema_name = quote_table_name(archive_schema_name)
      def quoted_replay_schema_name = quote_table_name(replay_schema_name)
      def quoted_view_schema_name = quote_table_name(view_schema_name)

      def connection = ActiveRecord::Base.connection

      def transaction(...) = Sequent.configuration.transaction_provider.transactional(...)
    end
  end
end
