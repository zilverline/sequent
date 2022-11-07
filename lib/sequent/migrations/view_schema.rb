# frozen_string_literal: true

require 'parallel'
require 'postgresql_cursor'

require_relative '../support/database'
require_relative '../sequent'
require_relative '../util/timer'
require_relative '../util/printer'
require_relative './projectors'
require_relative 'planner'
require_relative 'executor'
require_relative 'sql'

module Sequent
  module Migrations
    class MigrationError < RuntimeError; end

    ##
    # ViewSchema is used for migration of you view_schema. For instance
    # when you create new Projectors or change existing Projectors.
    #
    # The following migrations are supported:
    #
    # - ReplayTable (Projector migrations)
    # - AlterTable (For instance if you introduce a new column)
    #
    # To maintain your migrations you need to:
    # 1. Create a class that extends `Sequent::Migrations::Projectors`
    #    and specify in `Sequent.configuration.migrations_class_name`
    # 2. Define per version which migrations you want to execute
    #    See the definition of `Sequent::Migrations::Projectors.versions` and `Sequent::Migrations::Projectors.version`
    # 3. Specify in Sequent where your sql files reside (Sequent.configuration.migration_sql_files_directory)
    # 4. Ensure that you add %SUFFIX% to each name that needs to be unique in postgres
    #    (like TABLE names, INDEX names, PRIMARY KEYS)
    #    E.g. `create table foo%SUFFIX% (id serial NOT NULL, CONSTRAINT foo_pkey%SUFFIX% PRIMARY KEY (id))`
    # 5. If you want to run an `alter_table` migration ensure that
    #   a sql file named `table_name_VERSION.sql` exists.
    #
    # Example:
    #
    # class AppMigrations < Sequent::Migrations::Projectors
    #   def self.version
    #     '3'
    #   end
    #
    #   def self.versions
    #     {
    #       '1' => [Sequent.all_projectors],
    #       '2' => [
    #         UserProjector,
    #         InvoiceProjector,
    #       ],
    #       '3' => [
    #         Sequent::Migrations.alter_table(UserRecord)
    #       ]
    #
    #     }
    #   end
    #
    # end
    class ViewSchema
      ALLOWED_REPLAY_EXPONENT = (1..4)

      include Sequent::Util::Timer
      include Sequent::Util::Printer
      include Sql

      class Versions < Sequent::ApplicationRecord; end
      class ReplayedIds < Sequent::ApplicationRecord; end

      attr_reader :view_schema, :db_config, :logger

      class << self
        # @see #create_view_tables
        # @param env [String] The environment used for connecting the database
        def create_view_tables(env:)
          fail ArgumentError, 'env is required' if env.blank?

          db_config = Sequent::Support::Database.read_config(env)
          Sequent::Support::Database.establish_connection(db_config)
          new(db_config: db_config).create_view_tables
        end

        # @see #create_view_schema_if_not_exists
        # @param env [String] The environment used for connecting the database
        def create_view_schema_if_not_exists(env:)
          fail ArgumentError, 'env is required' if env.blank?

          db_config = Sequent::Support::Database.read_config(env)
          Sequent::Support::Database.establish_connection(db_config)

          new(db_config: db_config).create_view_schema_if_not_exists
        end
      end

      def initialize(db_config:)
        @db_config = db_config
        @view_schema = Sequent.configuration.view_schema_name
        @logger = Sequent.logger
      end

      ##
      # Returns the current version from the database
      def current_version
        Versions.order('version desc').limit(1).first&.version || 0
      end

      ##
      # Utility method that creates all tables in the view schema
      #
      # This method is mainly useful in test scenario to just create
      # the entire view schema without replaying the events
      def create_view_tables
        create_view_schema_if_not_exists
        return if Sequent.migration_class == Sequent::Migrations::Projectors
        return if Sequent.new_version == current_version

        in_view_schema do
          Sequent::Core::Migratable.all.flat_map(&:managed_tables).each do |table|
            sql_file = "#{Sequent.configuration.migration_sql_files_directory}/#{table.table_name}.sql"
            statements = sql_file_to_statements(sql_file) do |raw_sql|
              raw_sql.remove('%SUFFIX%')
            end
            statements.each { |statement| exec_sql(statement) }

            indexes_file_name = "#{Sequent.configuration.migration_sql_files_directory}/#{table.table_name}.indexes.sql"
            if File.exist?(indexes_file_name)
              statements = sql_file_to_statements(indexes_file_name) { |raw_sql| raw_sql.remove('%SUFFIX%') }
              statements.each(&method(:exec_sql))
            end
          end
          Versions.create!(version: Sequent.new_version)
        end
      end

      ##
      # Utility method that replays events for all managed_tables from all Sequent::Core::Projector's
      #
      # This method is mainly useful in test scenario's or development tasks
      def replay_all!(group_exponent: 1)
        replay!(
          Sequent.configuration.online_replay_persistor_class.new,
          projectors: Core::Migratable.projectors,
          group_exponent: group_exponent,
        )
      end

      ##
      # Utility method that creates the view_schema and the meta data tables
      #
      # This method is mainly useful during an initial setup of the view schema
      def create_view_schema_if_not_exists
        exec_sql(%(CREATE SCHEMA IF NOT EXISTS #{view_schema}))
        in_view_schema do
          exec_sql(<<~SQL.chomp)
            CREATE TABLE IF NOT EXISTS #{Versions.table_name} (version integer NOT NULL, CONSTRAINT version_pk PRIMARY KEY(version))
          SQL
          exec_sql(<<~SQL.chomp)
            CREATE TABLE IF NOT EXISTS #{ReplayedIds.table_name} (event_id bigint NOT NULL, CONSTRAINT event_id_pk PRIMARY KEY(event_id))
          SQL
        end
      end

      def plan
        @plan ||= Planner.new(Sequent.migration_class.versions).plan(current_version, Sequent.new_version)
      end

      def executor
        @executor ||= Executor.new
      end

      ##
      # First part of a view schema migration
      #
      # Call this method while your application is running.
      # The online part consists of:
      #
      # 1. Ensure any previous migrations are cleaned up
      # 2. Create new tables for the Projectors which need to be migrated to the new version
      #   These tables will be called `table_name_VERSION`.
      # 3. Replay all events to populate the tables
      #   It keeps track of all events that are already replayed.
      #
      # If anything fails an exception is raised and everything is rolled back
      #
      def migrate_online
        return if Sequent.new_version == current_version

        ensure_version_correct!

        in_view_schema do
          truncate_replay_ids_table!

          drop_old_tables(Sequent.new_version)
          executor.execute_online(plan)
        end

        replay!(Sequent.configuration.online_replay_persistor_class.new) if plan.projectors.any?

        in_view_schema do
          executor.create_indexes_after_execute_online(plan)
        end
        # rubocop:disable Lint/RescueException
      rescue Exception => e
        # rubocop:enable Lint/RescueException
        rollback_migration
        raise e
      end

      ##
      # Last part of a view schema migration
      #
      # +You have to ensure no events are being added to the event store while this method is running.+
      # For instance put your application in maintenance mode.
      #
      # The offline part consists of:
      #
      # 1. Replay all events not yet replayed since #migration_online
      # 2. Within a single transaction do:
      # 2.1 Rename current tables with the +current version+ as SUFFIX
      # 2.2 Rename the new tables and remove the +new version+ suffix
      # 2.3 Add the new version in the +Versions+ table
      # 3. Performs cleanup of replayed event ids
      #
      # If anything fails an exception is raised and everything is rolled back
      #
      # When this method succeeds you can safely start the application from Sequent's point of view.
      #
      def migrate_offline
        return if Sequent.new_version == current_version

        ensure_version_correct!

        executor.set_table_names_to_new_version(plan)

        # 1 replay events not yet replayed
        if plan.projectors.any?
          replay!(
            Sequent.configuration.offline_replay_persistor_class.new,
            exclude_ids: true,
            group_exponent: 1,
          )
        end

        in_view_schema do
          Sequent::ApplicationRecord.transaction do
            # 2.1, 2.2
            executor.execute_offline(plan, current_version)
            # 2.3 Create migration record
            Versions.create!(version: Sequent.new_version)
          end

          # 3. Truncate replayed ids
          truncate_replay_ids_table!
        end
        logger.info "Migrated to version #{Sequent.new_version}"
        # rubocop:disable Lint/RescueException
      rescue Exception => e
        # rubocop:enable Lint/RescueException
        rollback_migration
        raise e
      end

      private

      def ensure_version_correct!
        create_view_schema_if_not_exists
        new_version = Sequent.new_version

        if new_version < current_version
          fail ArgumentError,
               "new_version [#{new_version}] must be greater or equal to current_version [#{current_version}]"
        end
      end

      def replay!(replay_persistor, projectors: plan.projectors, exclude_ids: false, group_exponent: 3)
        logger.info "group_exponent: #{group_exponent.inspect}"

        with_sequent_config(replay_persistor, projectors) do
          logger.info 'Start replaying events'

          number_of_groups = 16**group_exponent
          time("#{number_of_groups} groups replayed") do
            event_types = projectors.flat_map { |projector| projector.message_mapping.keys }.uniq.map(&:name)
            disconnect!

            groups = aggregate_id_ranges(group_exponent)

            @connected = false
            # using `map_with_index` because https://github.com/grosser/parallel/issues/175
            result = Parallel.map_with_index(
              groups,
              in_processes: Sequent.configuration.number_of_replay_processes,
            ) do |aggregate_id_range, index|
              @connected ||= establish_connection
              msg = <<~EOS.chomp
                Group (#{aggregate_id_range.first}-#{aggregate_id_range.last}) #{index + 1}/#{number_of_groups} replayed
              EOS
              time(msg) do
                replay_events(aggregate_id_range, event_types, exclude_ids, replay_persistor, &insert_ids)
              end
              nil
            rescue StandardError => e
              logger.error "Replaying failed for ids: ^#{aggregate_id_range.first} - #{aggregate_id_range.last}"
              logger.error '+++++++++++++++ ERROR +++++++++++++++'
              recursively_print(e)
              raise Parallel::Kill # immediately kill all sub-processes
            end
            establish_connection
            fail if result.nil?
          end
        end
      end

      def replay_events(aggregate_id_range, event_types, exclude_already_replayed, replay_persistor, &on_progress)
        Sequent.configuration.event_store.replay_events_from_cursor(
          block_size: 1000,
          get_events: -> { event_stream(aggregate_id_range, event_types, exclude_already_replayed) },
          on_progress: on_progress,
        )

        replay_persistor.commit

        # Also commit all specific declared replay persistors on projectors.
        Sequent.configuration.event_handlers.select { |e| e.class.replay_persistor }.each(&:commit)
      end

      def rollback_migration
        disconnect!
        establish_connection
        drop_old_tables(Sequent.new_version)

        truncate_replay_ids_table!
        executor.reset_table_names(plan)
      end

      def truncate_replay_ids_table!
        exec_sql("truncate table #{ReplayedIds.table_name}")
      end

      def aggregate_id_ranges(exponent)
        fail "Exponent must be in range #{ALLOWED_REPLAY_EXPONENT}" unless ALLOWED_REPLAY_EXPONENT.include? exponent

        (0...16**exponent).map do |i|
          prefix = format('%0*x', exponent, i)
          lowerbound = prefix + '00000000-0000-0000-0000-000000000000'[exponent..-1]
          upperbound = prefix + 'ffffffff-ffff-ffff-ffff-ffffffffffff'[exponent..-1]
          (lowerbound .. upperbound)
        end
      end

      def in_view_schema(&block)
        Sequent::Support::Database.with_schema_search_path(view_schema, db_config, &block)
      end

      def drop_old_tables(new_version)
        versions_to_check = (current_version - 10)..new_version
        old_tables = versions_to_check.flat_map do |old_version|
          exec_sql(<<~SQL).flat_map(&:values)
            select table_name from information_schema.tables where table_schema = '#{Sequent.configuration.view_schema_name}' and table_name LIKE '%_#{old_version}'
          SQL
        end
        old_tables.each do |old_table|
          exec_sql("DROP TABLE #{Sequent.configuration.view_schema_name}.#{old_table} CASCADE")
        end
      end

      def insert_ids
        ->(progress, done, ids) do
          unless ids.empty?
            exec_sql(
              "insert into #{ReplayedIds.table_name} (event_id) values #{ids.map do |id|
                                                                           "(#{id})"
                                                                         end.join(',')}",
            )
          end
          Sequent::Core::EventStore::PRINT_PROGRESS[progress, done, ids] if progress > 0
        end
      end

      def with_sequent_config(replay_persistor, projectors, &block)
        old_config = Sequent.configuration

        config = Sequent.configuration.dup

        replay_projectors = projectors.map do |projector_class|
          projector_class.new(projector_class.replay_persistor || replay_persistor)
        end
        config.transaction_provider = Sequent::Core::Transactions::NoTransactions.new
        config.event_handlers = replay_projectors

        Sequent::Configuration.restore(config)

        block.call
      ensure
        Sequent::Configuration.restore(old_config)
      end

      def event_stream(aggregate_id_range, event_types, exclude_already_replayed)
        event_stream = Sequent.configuration.event_record_class
          .where(event_type: event_types)
          .where('aggregate_id BETWEEN ? AND ?', aggregate_id_range.first, aggregate_id_range.last)
        if exclude_already_replayed
          event_stream = event_stream
            .where("NOT EXISTS (SELECT 1 FROM #{ReplayedIds.table_name} WHERE event_id = event_records.id)")
        end
        event_stream = event_stream.where('event_records.created_at > ?', 1.day.ago) if exclude_already_replayed
        event_stream.order('sequence_number ASC').select('id, event_type, event_json, sequence_number')
      end

      ## shortcut methods
      def disconnect!
        Sequent::Support::Database.disconnect!
      end

      def establish_connection
        Sequent::Support::Database.establish_connection(db_config)
      end
    end
  end
end
