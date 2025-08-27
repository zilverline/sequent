# frozen_string_literal: true

require 'open3'
require_relative 'event_replayer'
require 'active_support/core_ext/integer/inflections'

module Sequent
  module Migrations
    class ReplayState < ActiveRecord::Base
      scope :replaying, -> { where(state: %w[replaying catching_up]) }

      REPLAY_STATES = %w[
        created
        prepared
        replaying
        catching_up
        replayed
        optimized
        live
        aborted
        failed
      ].freeze

      validates :state, presence: true, inclusion: REPLAY_STATES
    end

    # Replay a set of projectors while the system is running and atomically replace the existing
    # tables with the replayed tables when completed.
    class ProjectorsReplayer
      extend Forwardable
      include EventReplayer

      attr_reader :projector_classes, :managed_tables, :state

      def_delegators :connection, :exec_update, :exec_query, :quote_column_name, :quote_string, :quote_table_name

      def initialize(state:)
        super()

        @projector_classes = state.projectors.map { |p| Class.const_get(p) }
        if (unsupported = @projector_classes.reject { |p| p < Sequent::Core::Projector }).present?
          fail ArgumentError, "unsupported projector(s) #{unsupported.join(', ')}"
        end

        @state = state
        @managed_tables = projector_classes.flat_map(&:managed_tables).sort_by(&:name)
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
        pg_dump_path = locate_command('pg_dump')
        psql_path = locate_command('psql')

        with_locked_state do
          verify_state 'preparing for replay can only be performed when', 'created'

          log_and_exec_update("DROP SCHEMA IF EXISTS #{quoted_replay_schema_name} CASCADE")
          log_and_exec_update("CREATE SCHEMA #{quoted_replay_schema_name}")
        end

        # Start new transaction to ensure replay schema is visible when running pg_dump and psql.
        with_locked_state do
          verify_state 'preparing for replay can only be performed when', 'created'

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

          @state.index_definitions = query_index_definitions
          @state.table_cluster_indexes = query_table_cluster_indexes

          drop_indexes_not_needed_for_replay

          Sequent::Core::Projectors.register_replaying_projectors!(projector_classes)

          @state.state = 'prepared'
          @state.save!
        rescue StandardError
          mark_replay_failed!
          raise
        end
      end

      def perform_initial_replay(
        replay_group_target_size: Sequent.configuration.replay_group_target_size,
        number_of_replay_processes: Sequent.configuration.number_of_replay_processes
      )
        maximum_xact_id_exclusive = with_locked_state do
          verify_state 'initial replay can only be performed when', 'prepared'
          verify_replaying_projector_versions

          non_empty_tables = @managed_tables.select do |table|
            exec_query("SELECT 1 FROM #{quote_table_name(replay_schema_name)}.#{table.quoted_table_name} LIMIT 1")
              .to_a
              .present?
          end
          fail "managed tables #{non_empty_tables.join(', ')} are not empty" unless non_empty_tables.empty?

          @state.state = 'replaying'
          @state.save!

          Sequent::Support::Database.current_snapshot_xmin_xact_id
        end

        begin
          replay!(
            Sequent.configuration.online_replay_persistor_class.new,
            projector_classes: @projector_classes,
            minimum_xact_id_inclusive: nil,
            maximum_xact_id_exclusive: maximum_xact_id_exclusive,
            with_group:,
            replay_group_target_size:,
            number_of_replay_processes:,
          )

          with_locked_state do
            verify_replaying_projector_versions
            fail 'internal error' unless @state.state == 'replaying'

            @state.state = 'replayed'
            @state.continue_replay_at_xact_id = maximum_xact_id_exclusive
            @state.save!
          end
        rescue StandardError
          mark_replay_failed!
          raise
        end
      end

      def perform_incremental_replay(
        replay_group_target_size: Sequent.configuration.replay_group_target_size,
        number_of_replay_processes: Sequent.configuration.number_of_replay_processes
      )
        maximum_xact_id_exclusive, saved_state = with_locked_state do
          verify_state 'catching up can only be performed when', 'replayed', 'optimized'
          verify_replaying_projector_versions

          saved_state = @state.state

          @state.state = 'catching_up'
          @state.save!

          [Sequent::Support::Database.current_snapshot_xmin_xact_id, saved_state]
        end

        begin
          replay!(
            Sequent.configuration.offline_replay_persistor_class.new,
            projector_classes: @projector_classes,
            minimum_xact_id_inclusive: @state.continue_replay_at_xact_id,
            maximum_xact_id_exclusive: maximum_xact_id_exclusive,
            with_group:,
            replay_group_target_size:,
            number_of_replay_processes:,
          )

          with_locked_state do
            verify_replaying_projector_versions
            fail 'internal error' unless @state.state == 'catching_up'

            @state.state = saved_state
            @state.continue_replay_at_xact_id = maximum_xact_id_exclusive
            @state.save!
          end
        rescue StandardError
          mark_replay_failed!
          raise
        end
      end

      def prepare_for_activation!
        with_locked_state do
          verify_state 'activation can only be performed when', 'replayed'
          verify_replaying_projector_versions
        end

        vacuum_tables

        with_locked_state do
          verify_state 'activation can only be performed when', 'replayed'
          verify_replaying_projector_versions

          recreate_dropped_indexes
          analyze_tables

          @state.state = 'optimized'
          @state.save!
        end
      end

      def activate!
        with_locked_state do
          verify_state 'going live can only be performed when', 'optimized'
          verify_replaying_projector_versions

          exec_update("SET LOCAL lock_timeout TO '1s'")

          Sequent::Core::Projectors.register_activating_projectors!(projector_classes)

          lock_view_schema_tables_for_exclusive_access(managed_tables)

          event_types = projector_classes.flat_map { |p| p.message_mapping.keys }.uniq.map(&:name)
          event_type_ids = Internal::EventType.where(type: event_types).pluck(:id)

          Sequent::Support::Database.with_search_path(replay_schema_name, event_store_schema_name) do
            with_sequent_config(
              Sequent.configuration.offline_replay_persistor_class.new,
              projector_classes,
            ) do
              replay_events(
                -> {
                  event_stream(nil..nil, event_type_ids, @state.continue_replay_at_xact_id, nil)
                },
                Sequent.configuration.offline_replay_persistor_class.new,
              ) { |progress| }
            end
          end

          log_and_exec_update("DROP SCHEMA IF EXISTS #{quoted_archive_schema_name} CASCADE")
          log_and_exec_update("CREATE SCHEMA #{quoted_archive_schema_name}")

          replace_replayed_tables_in_view_schema(managed_tables)

          log_and_exec_update("DROP SCHEMA IF EXISTS #{quoted_replay_schema_name} CASCADE")

          Sequent::Core::Projectors.register_active_projectors!(projector_classes)

          @state.state = 'live'
          @state.save!
        end
      end

      def abort!
        with_locked_state do
          Sequent::Core::Projectors.abort_replaying_projectors(projector_classes)

          @state.state = 'aborted'
          @state.save!

          log_and_exec_update("DROP SCHEMA IF EXISTS #{quoted_replay_schema_name} CASCADE")
        end
      end

      private

      def verify_state(message, *expected_states)
        fail "#{message} current state is #{expected_states.join(' or ')}" unless expected_states.include?(@state.state)
      end

      def verify_replaying_projector_versions
        replaying = Sequent::Core::Projectors.projector_states.select { |_, p| p.replaying_version.present? }
        mismatched = projector_classes.reject { |c| replaying[c.name]&.replaying_version == c.version }
        if mismatched.present?
          fail "running projectors #{mismatched.map(&:name).join(', ')} versions do not match replay set"
        end

        superfluous = replaying.keys - projector_classes.map(&:name)
        if superfluous.present?
          fail "replay set projectors #{superfluous.map(&:name).join(', ')} are not in running projector set"
        end
      end

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

      def lock_view_schema_tables_for_exclusive_access(tables)
        Sequent::Support::Database.with_search_path(view_schema_name) do
          exec_update("LOCK TABLE #{tables.map(&:quoted_table_name).join(', ')} IN ACCESS EXCLUSIVE MODE")
        end
      end

      def replace_replayed_tables_in_view_schema(tables)
        tables.flat_map do |table|
          [table.table_name, *query_partition_names(view_schema_name, table.table_name)]
        end.each do |table_name|
          log_and_exec_update(<<~SQL, 'replace_table')
            ALTER TABLE IF EXISTS #{quoted_view_schema_name}.#{quote_table_name(table_name)} SET SCHEMA #{quoted_archive_schema_name}
          SQL
          log_and_exec_update(<<~SQL, 'replace_table')
            ALTER TABLE #{quoted_replay_schema_name}.#{quote_table_name(table_name)} SET SCHEMA #{quoted_view_schema_name}
          SQL
        end
      end

      def event_store_schema_name = Sequent.configuration.event_store_schema_name
      def view_schema_name = Sequent.configuration.view_schema_name
      def replay_schema_name = Sequent.configuration.replay_schema_name
      def archive_schema_name = Sequent.configuration.archive_schema_name

      def quoted_archive_schema_name = quote_table_name(archive_schema_name)
      def quoted_replay_schema_name = quote_table_name(replay_schema_name)
      def quoted_view_schema_name = quote_table_name(view_schema_name)

      def connection = ActiveRecord::Base.connection

      def with_locked_state(...) = @state.with_lock('FOR NO KEY UPDATE', ...)

      # Adapted from https://github.com/rails/rails/blob/main/activerecord/lib/active_record/tasks/postgresql_database_tasks.rb#L80
      def psql_env
        {}.tap do |env|
          db_config = ActiveRecord::Base.connection_db_config.configuration_hash
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

      def query_table_cluster_indexes
        rows = exec_query(<<~SQL, 'clustered tables', [replay_schema_name])
          SELECT c.relname AS table_name,
                 ic.relname AS index_name
            FROM pg_namespace ns
            JOIN pg_class c ON c.relnamespace = ns.oid
            JOIN pg_index i ON c.oid = i.indrelid
            JOIN pg_class ic ON i.indexrelid = ic.oid
           WHERE ns.nspname = $1
             AND c.relkind = 'r'  -- only regular tables, not partitioned tables
             AND i.indisclustered
        SQL
        rows.pluck('table_name', 'index_name').to_h
      end

      def query_index_definitions
        index_definitions = exec_query(<<~SQL, 'index definitions', [replay_schema_name])
          SELECT * FROM pg_indexes WHERE schemaname = $1
        SQL
        index_definitions.pluck('indexname', 'indexdef').to_h
      end

      def drop_indexes_not_needed_for_replay
        disposable_indexes = exec_query(<<~SQL, 'disposable indexes', [replay_schema_name]).pluck('index_name')
          SELECT ic.relname AS index_name
            FROM pg_namespace ns
            JOIN pg_class c ON c.relnamespace = ns.oid
            JOIN pg_index i ON c.oid = i.indrelid
            JOIN pg_class ic ON i.indexrelid = ic.oid
           WHERE ns.nspname = $1
             AND c.relkind = 'r'  -- only drop indexes on real tables, not on partitioned tables
             AND NOT i.indisunique
             AND NOT i.indisprimary
             AND NOT i.indisexclusion
        SQL
        additional_replay_indexes = /^#{Regexp.union(@projector_classes.map(&:additional_replay_indexes).flatten)}$/
        droppable_indexes = disposable_indexes.grep_v(additional_replay_indexes)
        droppable_indexes.each do |index_name|
          exec_update("DROP INDEX #{quoted_replay_schema_name}.#{quote_table_name(index_name)}")
        end
      end

      def recreate_dropped_indexes
        @state.index_definitions.each_key do |name|
          create_index_if_missing(name)
        end
      end

      def create_index_if_missing(index_name)
        exists = connection.select_value(<<~SQL, 'index exists?', [replay_schema_name, index_name])
          SELECT EXISTS(SELECT 1 FROM pg_indexes WHERE schemaname = $1 AND indexname = $2)
        SQL
        unless exists
          definition = @state.index_definitions[index_name]
          log_and_exec_update_update(definition)
        end
      end

      def vacuum_tables
        clustered_tables, non_clustered_tables = @managed_tables.partition do |table|
          @state.table_cluster_indexes.key?(table.table_name)
        end

        clustered_tables.each do |table|
          cluster_index_name = @state.table_cluster_indexes[table.table_name]
          create_index_if_missing(cluster_index_name)

          log_and_exec_update(<<~SQL, 'cluster table')
            CLUSTER #{quoted_replay_schema_name}.#{table.quoted_table_name} USING #{quote_table_name(cluster_index_name)}
          SQL
        end
        non_clustered_tables.each do |table|
          log_and_exec_update("VACUUM FULL #{quoted_replay_schema_name}.#{table.quoted_table_name}", 'vacuum table')
        end
      end

      def analyze_tables
        @managed_tables.each do |table|
          log_and_exec_update("ANALYZE #{quoted_replay_schema_name}.#{table.quoted_table_name}", 'analyze table')
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
           ORDER BY 1
        SQL
      end

      def locate_command(cmd)
        path, status = Open3.capture2("which #{cmd}")
        fail 'cannot determine full path of pg_dump executable' unless status.success?

        path.strip
      end

      def mark_replay_failed!
        @state.reload.with_lock('FOR NO KEY UPDATE') do
          @state.state = 'failed'
          @state.save!
        end
      end

      def log_and_exec_update(sql, ...)
        Sequent.logger.info(sql.strip)
        exec_update(sql, ...)
      end
    end
  end
end
