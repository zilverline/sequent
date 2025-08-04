# frozen_string_literal: true

require 'open3'
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

      def self.create!(projector_classes:)
        fail 'at least one projector must be specified' if projector_classes.empty?

        state = ReplayState.create!(state: 'created', projectors: projector_classes.map(&:name))
        new(state:)
      end

      def self.resume_from_database
        state = ReplayState.where.not(state: %w[done aborted]).last!
        new(state:)
      end

      def prepare_for_replay
        exec_update("CREATE SCHEMA IF NOT EXISTS #{replay_schema_name}")

        with_locked_state do
          fail 'initial replay can only be performed when current state is `created`' unless @state.state == 'created'

          pg_dump_path = locate_command('pg_dump')
          psql_path = locate_command('psql')

          pg_dump_args = %w[--schema-only --quote-all-identifiers --strict-names] +
                         @managed_tables.map do |table|
                           "--table-and-children=#{view_schema_name}.#{table.table_name}"
                         end

          ddl, stderr, status = Open3.capture3(psql_env, pg_dump_path, *pg_dump_args)
          fail "failed to dump view schema projector tables #{stderr}" unless status.success?

          psql_args = %w[--single-transaction --quiet --no-psqlrc --set=ON_ERROR_STOP=1 --file=-]
          Open3.popen2e(psql_env, psql_path.strip, *psql_args) do |stdin, stdout_and_stderr, wait_thread|
            replay_ddl = ddl.gsub(/#{quoted_view_schema_name}\./, "#{quoted_replay_schema_name}.")

            stdin.write(replay_ddl)
            stdin.close

            output = stdout_and_stderr.read
            stdout_and_stderr.close

            status = wait_thread.value
            fail "failed to create replay schema tables: #{output}" unless status.success?
          end

          @state.state = 'prepared'
          @state.save!
        end

        self
      rescue StandardError
        mark_replay_failed!
        raise
      end

      def perform_initial_replay
        maximum_xact_id_exclusive = with_locked_state do
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

        with_locked_state do
          fail 'internal error' unless @state.state == 'initial_replay'

          @state.state = 'ready_for_activation'
          @state.continue_replay_at_xact_id = maximum_xact_id_exclusive
          @state.save!
        end
      rescue StandardError
        mark_replay_failed!
        raise
      end

      def perform_incremental_replay
        maximum_xact_id_exclusive = with_locked_state do
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

        with_locked_state do
          fail 'internal error' unless @state.state == 'incremental_replay'

          @state.state = 'ready_for_activation'
          @state.continue_replay_at_xact_id = maximum_xact_id_exclusive
          @state.save!
        end
      rescue StandardError
        mark_replay_failed!
        raise
      end

      def activate!
        with_locked_state do
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

          exec_update("DROP SCHEMA IF EXISTS #{quoted_replay_schema_name} CASCADE")

          @state.state = 'done'
          @state.save!
        end
      end

      def done!
        with_locked_state do
          @state.state = 'done'
          @state.save!

          exec_update("DROP SCHEMA IF EXISTS #{quoted_replay_schema_name} CASCADE")
        end
      end

      def abort!
        with_locked_state do
          @state.state = 'aborted'
          @state.save!

          exec_update("DROP SCHEMA IF EXISTS #{quoted_replay_schema_name} CASCADE")
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
        tables.flat_map do |table|
          [table.table_name, *query_partition_names(view_schema_name, table.table_name)]
        end.each do |table_name|
          exec_update(<<~SQL, 'replace_table')
            ALTER TABLE IF EXISTS #{quoted_view_schema_name}.#{quote_table_name(table_name)}
              SET SCHEMA #{quoted_archive_schema_name}
          SQL
          exec_update(<<~SQL, 'replace_table')
            ALTER TABLE #{quoted_replay_schema_name}.#{quote_table_name(table_name)}
              SET SCHEMA #{quoted_view_schema_name}
          SQL
        end
      end

      def archive_schema_name = 'archive_schema'
      def event_store_schema_name = Sequent.configuration.event_store_schema_name
      def view_schema_name = Sequent.configuration.view_schema_name

      def quoted_archive_schema_name = quote_table_name(archive_schema_name)
      def quoted_replay_schema_name = quote_table_name(replay_schema_name)
      def quoted_view_schema_name = quote_table_name(view_schema_name)

      def connection = ActiveRecord::Base.connection

      def with_locked_state(...) = @state.with_lock('FOR NO KEY UPDATE', ...)

      # Adapted from https://github.com/rails/rails/blob/main/activerecord/lib/active_record/tasks/postgresql_database_tasks.rb#L80
      def psql_env
        {}.tap do |env|
          env['PGHOST'] = db_config[:host] if db_config[:host]
          env['PGDATABASE'] = db_config[:database] if db_config[:database]
          env['PGPORT'] = db_config[:port].to_s if db_config[:port]
          env['PGPASSWORD'] = db_config[:password].to_s if db_config[:password]
          env['PGUSER'] = db_config[:username].to_s if db_config[:username]
          env['PGSSLMODE'] = db_config[:sslmode].to_s if db_config[:sslmode]
          env['PGSSLCERT'] = db_config[:sslcert].to_s if db_config[:sslcert]
          env['PGSSLKEY'] = db_config[:sslkey].to_s if db_config[:sslkey]
          env['PGSSLROOTCERT'] = db_config[:sslrootcert].to_s if db_config[:sslrootcert]
        end
      end

      def query_partition_names(schema_name, parent_table_name)
        exec_query(<<~SQL, 'query_partitions', [schema_name, parent_table_name]).map { |row| row['partition_name'] }
          WITH RECURSIVE inh AS (
            SELECT i.inhrelid, NULL::text AS parent
              FROM pg_catalog.pg_inherits i
              JOIN pg_catalog.pg_class cl ON i.inhparent = cl.oid
              JOIN pg_catalog.pg_namespace nsp ON cl.relnamespace = nsp.oid
             WHERE nsp.nspname = $1
               AND cl.relname = $2
            UNION ALL
            SELECT i.inhrelid, (i.inhparent::regclass)::text
              FROM inh
              JOIN pg_catalog.pg_inherits i ON inh.inhrelid = i.inhparent
          )
          SELECT c.relname AS partition_name
            FROM inh
            JOIN pg_catalog.pg_class c ON inh.inhrelid = c.oid
        SQL
      end

      def locate_command(cmd)
        path, status = Open3.capture2("which #{cmd}")
        fail 'cannot determine full path of pg_dump executable' unless status.success?

        path.strip
      end

      def mark_replay_failed!
        @state.with_lock('FOR NO KEY UPDATE') do
          @state.state = 'failed'
          @state.save!
        end
      end
    end
  end
end
