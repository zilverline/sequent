# frozen_string_literal: true

require 'active_record'
require 'rake'
require 'rake/tasklib'

require 'sequent/support'
require 'sequent/migrations/view_schema'
require 'sequent/migrations/sequent_schema'
require_relative 'migration_files'

module Sequent
  module Rake
    class MigrationTasks < ::Rake::TaskLib
      include ::Rake::DSL
      include ActiveRecord::Tasks

      def db_config
        ActiveRecord::Base.configurations.find_db_config(@env)
      end

      def register_tasks!
        namespace :sequent do
          desc <<~EOS
            Set the SEQUENT_ENV to RAILS_ENV or RACK_ENV if not already set
          EOS
          task :set_env_var do
            ENV['SEQUENT_ENV'] ||= ENV['RAILS_ENV'] || ENV['RACK_ENV']
          end

          desc <<~EOS
            Rake task that runs before all sequent rake tasks and after the environment is set.
            Hook applications can use to for instance run other rake tasks:

              Rake::Task['sequent:init'].enhance(['my_task'])

          EOS
          task init: :set_env_var

          task connect: :init do
            ensure_sequent_env_set!
            ActiveRecord::Base.establish_connection(@env.to_sym)
          end

          namespace :install do
            desc <<~EOS
              Copy (new) Sequent database migration files to your projects migrations directory
            EOS
            task :migrations do
              MigrationFiles.new.copy('./db/migrate')
            end
          end

          namespace :register do
            desc <<~EOS
              Register all aggregate root, command, and event types in the database type tables

              NOTE make sure to load all Ruby classes before running this task!
            EOS
            task types: %i[sequent:connect] do
              ensure_sequent_env_set!

              Sequent.configuration.event_store.register_types!
              Sequent.logger.info 'Registered aggregate root, command, and event types'
            end

            desc <<~EOS
              Register the required snapshot version for each aggregate root. This will ensure the snapshotter
              starts snapshotting with the right snapshot version.

              NOTE make sure to load all Ruby classes before running this task!
            EOS
            task snapshot_versions: %i[sequent:connect] do
              ensure_sequent_env_set!

              Sequent.configuration.event_store.register_snapshot_versions!
              Sequent.logger.info 'Registered required snapshot versions'
            end
          end

          desc 'Creates sequent view schema if not exists and runs internal migrations'
          task create_and_migrate_sequent_view_schema: ['sequent:init', :init] do
            ensure_sequent_env_set!
            Sequent::Migrations::ViewSchema.create_view_schema_if_not_exists(env: @env)
          end

          namespace :db do
            desc 'Creates the database and initializes the event_store schema for the current env'
            task create: ['sequent:init'] do
              ensure_sequent_env_set!
              Sequent::Support::Database.create!(db_config)
            end

            desc 'Apply Sequent event store migrations (NOT view schema projection migrations)'
            task migrate: %i[create sequent:connect] do
              ensure_sequent_env_set!

              ActiveRecord::MigrationContext.new('db/migrate').migrate
              ::Rake::Task['sequent:db:schema:dump'].invoke
            end

            namespace :schema do
              desc "Creates the database schema file 'db/structure.sql'"
              task dump: 'sequent:connect' do
                old_dump_schemas = ActiveRecord.dump_schemas
                begin
                  ActiveRecord.dump_schemas = nil
                  ActiveRecord::Tasks::DatabaseTasks.structure_dump_flags = %W[
                    --exclude-schema=#{Sequent.configuration.replay_schema_name}
                    --exclude-schema=#{Sequent.configuration.archive_schema_name}
                  ]
                  if Sequent.configuration.migrations_class
                    ActiveRecord::Tasks::DatabaseTasks.structure_dump_flags <<
                      "--exclude-schema=#{Sequent.configuration.view_schema_name}"
                  end
                  DatabaseTasks.dump_schema(db_config, :sql)
                ensure
                  ActiveRecord.dump_schemas = old_dump_schemas
                end
              end

              desc "Loads the database schema file 'db/structure.sql'"
              task load: 'sequent:connect' do
                DatabaseTasks.load_schema(db_config, :sql)
              end
            end

            desc 'Drops the database for the current env'
            task :drop, [:production] => ['sequent:init'] do |_t, args|
              ensure_sequent_env_set!

              if @env == 'production' && args[:production] != 'yes_drop_production'
                fail <<~EOS
                  Wont drop db in production unless you whitelist the environment as follows: rake sequent:db:drop[yes_drop_production]
                EOS
              end

              Sequent::Support::Database.drop!(db_config)
            end

            desc 'Creates the view schema for the current env'
            task create_view_schema: ['sequent:init'] do
              ensure_sequent_env_set!

              Sequent::Migrations::ViewSchema.create_view_schema_if_not_exists(env: @env)
            end

            desc 'Utility tasks that can be used to guard against unsafe usage of rails db:migrate directly'
            task :dont_use_db_migrate_directly do
              fail <<~EOS unless ENV['SEQUENT_MIGRATION_SCHEMAS'].present?
                Don't call rails db:migrate directly but wrap in your own task instead:

                  task :migrate_db do
                    ENV['SEQUENT_MIGRATION_SCHEMAS'] = 'public'
                    Rake::Task['db:migrate'].invoke
                  end

                You can choose whatever name for migrate_db you like.
              EOS
            end
          end

          namespace :migrate do
            desc <<~EOS
              Rake task that runs before all migrate rake tasks. Hook applications can use to for instance run other rake tasks.
            EOS
            task :init

            task connect: %i[sequent:connect init]

            desc 'Prints the current version in the database'
            task current_version: [:create_and_migrate_sequent_view_schema] do
              puts "Current version in the database is: #{Sequent::Migrations::Versions.current_version}"
            end

            desc 'Returns whether a migration is currently running'
            task check_running_migrations: [:create_and_migrate_sequent_view_schema] do
              if Sequent::Migrations::Versions.running.any?
                puts <<~EOS
                  Migration is running, current version: #{Sequent::Migrations::Versions.current_version},
                  target version #{Sequent::Migrations::Versions.version_currently_migrating}
                EOS
              else
                puts 'No running migrations'
              end
            end

            desc 'Returns whether a migration is pending'
            task check_pending_migrations: [:create_and_migrate_sequent_view_schema] do
              if Sequent.new_version != Sequent::Migrations::Versions.current_version
                puts <<~EOS
                  Migration is pending, current version: #{Sequent::Migrations::Versions.current_version},
                  pending version: #{Sequent.new_version}
                EOS
              else
                puts 'No pending migrations'
              end
            end

            desc 'Aborts if a migration is pending'
            task abort_if_pending_migrations: [:create_and_migrate_sequent_view_schema] do
              abort if Sequent.new_version != Sequent::Migrations::Versions.current_version
            end

            desc <<-EOS
              Shows the current status of the migrations
            EOS
            task status: :connect do
              ensure_sequent_env_set!
              view_schema = Sequent::Migrations::ViewSchema.new

              latest_done_version = Sequent::Migrations::Versions.done.latest
              latest_version = Sequent::Migrations::Versions.latest
              pending_version = Sequent.new_version
              case latest_version.status
              when Sequent::Migrations::Versions::DONE
                if pending_version == latest_version.version
                  puts "Current version #{latest_version.version}, no pending changes"
                else
                  puts "Current version #{latest_version.version}, pending version #{pending_version}"
                end
              when Sequent::Migrations::Versions::MIGRATE_ONLINE_RUNNING
                puts "Online migration from #{latest_done_version.version} to #{latest_version.version} is running"
              when Sequent::Migrations::Versions::MIGRATE_ONLINE_FINISHED
                projectors = view_schema.plan.projectors
                event_types = projectors.flat_map { |projector| projector.message_mapping.keys }.uniq.map(&:name)

                current_snapshot_xmin_xact_id = Sequent::Support::Database.current_snapshot_xmin_xact_id
                pending_events = Sequent.configuration.event_record_class
                  .where(event_type: event_types)
                  .where('xact_id >= ?', current_snapshot_xmin_xact_id)
                  .count
                print <<~EOS
                  Online migration from #{latest_done_version.version} to #{latest_version.version} is finished.
                  #{current_snapshot_xmin_xact_id - latest_version.xmin_xact_id} transactions behind current state (#{pending_events} pending events).
                EOS
              when Sequent::Migrations::Versions::MIGRATE_OFFLINE_RUNNING
                puts "Offline migration from #{latest_done_version.version} to #{latest_version.version} is running"
              end
            end

            desc <<~EOS
              Migrates the Projectors while the app is running. Call +sequent:migrate:offline+ after this successfully completed.
            EOS
            task online: :connect do
              ensure_sequent_env_set!

              view_schema = Sequent::Migrations::ViewSchema.new
              view_schema.migrate_online
            end

            desc <<~EOS
              Migrates the events inserted while +online+ was running. It is expected +sequent:migrate:online+ ran first.
            EOS
            task offline: :connect do
              ensure_sequent_env_set!

              view_schema = Sequent::Migrations::ViewSchema.new
              view_schema.migrate_offline
            end

            desc <<~EOS
              Runs the projectors in replay mode without making any changes to the database, useful for (performance) testing against real data.

              Pass a regular expression as parameter to select the projectors to run, otherwise all projectors are selected.
            EOS
            task :dryrun, %i[regex group_target_size] => :connect do |_task, args|
              ensure_sequent_env_set!

              view_schema = Sequent::DryRun::ViewSchema.new
              Sequent.configuration.replay_group_target_size = group_target_size

              view_schema.migrate_dryrun(regex: args[:regex])
            end

            desc <<~EOS
              Loads all aggregates of the specified type (if any) and updates the aggregate's unique keys in the database.

              Use this after adding new unique key constraints to an aggregate to ensure every aggregate's unique keys
              are present in the database.
            EOS
            task :unique_keys, %i[aggregate_type group_size] => :connect do |_task, args|
              count = 0
              Sequent.configuration.event_store.event_streams_enumerator(
                aggregate_type: args[:aggregate_type],
                group_size: args[:group_size] || 100,
              ).each do |aggregate_ids|
                Sequent.configuration.transaction_provider.transactional do
                  aggregates = Sequent.configuration.aggregate_repository.load_aggregates(aggregate_ids)
                  Sequent.configuration.event_store.update_unique_keys(aggregates.map(&:event_stream))
                  count += aggregates.size
                  printf("\rUpdated unique keys for #{count} aggregates.")
                end
              end
              puts("\nDone.")
            end
          end

          namespace :aggregates do
            desc <<~EOS
              Rake task that runs before all aggregates rake tasks. Hook applications can use to for instance run other rake tasks.
            EOS
            task :init

            task connect: %i[sequent:connect init]

            desc <<~EOS
              Rake task to apply pending partition key changes to the event store. This task cannot be run while a view schema
              migration is running!
            EOS
            task :update_partition_keys, %i[limit] => :connect do |_t, args|
              limit = args['limit']&.to_i

              unless limit
                fail ArgumentError,
                     'usage rake sequent:aggregates:update_partition_keys[limit]'
              end

              total_count = Sequent::Internal::PartitionKeyChange.count
              Sequent.logger.info "Applying #{total_count} partition key changes (limited to #{limit})"

              begin
                applied_count = Sequent::Internal::PartitionKeyChange.update_aggregate_partition_keys(limit:)
                Sequent.logger.info "Applied #{applied_count} out of #{total_count} partition key changes"
              rescue Sequent::Migrations::ConcurrentMigration
                Sequent.logger.error 'View schema migration is active so not updating partition keys'
              end
            end
          end

          namespace :snapshots do
            desc <<~EOS
              Rake task that runs before all snapshots rake tasks. Hook applications can use to for instance run other rake tasks.
            EOS
            task :init

            task connect: %i[sequent:connect init]

            desc <<~EOS
              Takes up-to `limit` snapshots, starting with the highest priority aggregates (based on snapshot outdated time and number of events)
            EOS
            task :take_snapshots, %i[limit] => :connect do |_t, args|
              limit = args['limit']&.to_i

              unless limit
                fail ArgumentError,
                     'usage rake sequent:snapshots:take_snapshots[limit]'
              end

              aggregates = Sequent.configuration.event_store.select_aggregates_for_snapshotting(limit:)

              Sequent.logger.info "Taking #{aggregates.size} snapshots"
              aggregates.each do |aggregate|
                Sequent.command_service.execute_commands(
                  Sequent::Core::TakeSnapshot.new(aggregate_id: aggregate.aggregate_id),
                )
              end
            end

            desc <<~EOS
              Takes a new snapshot for the aggregate specified by `aggregate_id`
            EOS
            task :take_snapshot, %i[aggregate_id] => :connect do |_t, args|
              aggregate_id = args['aggregate_id']

              unless aggregate_id
                fail ArgumentError,
                     'usage rake sequent:snapshots:take_snapshot[aggregate_id]'
              end

              Sequent.command_service.execute_commands(Sequent::Core::TakeSnapshot.new(aggregate_id:))
            end

            desc <<~EOS
              Delete all aggregate snapshots, which can negatively impact performance of a running system.
            EOS
            task delete_all: :connect do
              Sequent.configuration.event_store.delete_all_snapshots
              Sequent.logger.info 'Deleted all aggregate snapshots from the event store'
            end

            desc <<~EOS
              Delete all aggregate snapshots with a lower snapshot version than currently supported.
            EOS
            task delete_unknown_snapshot_versions: :connect do
              Sequent.configuration.event_store.delete_unknown_snapshot_versions
              Sequent.logger.info 'Deleted all lower snapshot versions from the event store'
            end
          end

          namespace :projectors do
            desc 'shows the current status of the projectors'
            task status: :connect do
              format = "%-50s | %10s | %10s | %10s\n"
              printf format, 'Projector', 'active', 'activating', 'replaying'
              Sequent::Core::ProjectorState.order(:name).all.each do |s|
                printf format, s.name, s.active_version, s.activating_version, s.replaying_version
              end
            end

            desc <<~EOS
              Deactivates the specified projectors so they no longer process events.

              The managed tables are NOT removed or deleted so the data remains but is no longer updated
              when new events arrive. A deactivated projector can only be re-activated by replaying
              all its events and then activating the replayed projector.
            EOS
            task deactivate: :connect do |_t, args|
              projector_classes = args.extras.map { |name| Class.const_get(name) }
              Sequent::Core::Projectors.deactivate_projectors!(projector_classes)
            end

            namespace :replay do
              desc 'shows the current replay status'
              task status: :connect do
                replay_state = Sequent::Migrations::ReplayState.last
                if replay_state
                  show_replay_state(replay_state)
                else
                  Sequent.logger.info(
                    'replay state is not present, use sequent:projectors:replay:prepare to start replaying',
                  )
                end
              end

              desc <<~EOS
                Replay all projectors and go live
              EOS
              task all: %i[prepare replay catchup optimize catchup golive]

              desc <<~EOS
                Prepare the specified projectors for background replay

                Creates the `#{Sequent.configuration.replay_schema_name}` with the projector's tables copied from the
                `#{Sequent.configuration.view_schema_name}` (schema only, not including the table's data)
              EOS
              task prepare: :connect do |_t, args|
                projector_classes = args.extras.map { |name| Class.const_get(name) }.presence ||
                                    Sequent::Core::Migratable.all
                replayer = Sequent::Migrations::ProjectorsReplayer.create!(projector_classes:)
                replayer.prepare_for_replay
                show_replay_state(replayer.state)
              rescue NameError => e
                Sequent.logger.error("prepare: unknown projector '#{e.name}'")
                exit(1)
              end

              desc 'Abort the current background projector replay, completely deleting the `replay_schema`'
              task abort: :connect do
                replayer = Sequent::Migrations::ProjectorsReplayer.resume_from_database
                replayer.abort!
                show_replay_state(replayer.state)
              end

              desc <<~EOS
                Performs the initial replay of all applicable events from the event store

                Splits the aggregates into groups of approximately `replay_group_target_size`
                (default #{Sequent.configuration.replay_group_target_size}) events using `number_of_replay_processes`
                (default #{Sequent.configuration.number_of_replay_processes}) parallel worker processes.

                Once the initial replay has been completed you can catchup with incremental replay or optimize before
                going lie with the projectors.
              EOS
              task :replay,
                   %i[replay_group_target_size number_of_replay_processes] => :connect do |_t, args|
                     replay_group_target_size = args[:replay_group_target_size]&.to_i ||
                                                Sequent.configuration.replay_group_target_size
                     number_of_replay_processes = args[:number_of_replay_processes]&.to_i ||
                                                  Sequent.configuration.number_of_replay_processes

                     replayer = Sequent::Migrations::ProjectorsReplayer.resume_from_database
                     replayer.perform_initial_replay(replay_group_target_size:, number_of_replay_processes:)
                     show_replay_state(replayer.state)
                   end

              desc <<~EOS
                Performs replay of new event since last replay

                Splits the aggregates into groups of approximately `replay_group_target_size` (default #{Sequent.configuration.replay_group_target_size}) events
                using `number_of_replay_processes` (default #{Sequent.configuration.number_of_replay_processes}) parallel worker processes.
              EOS
              task :catchup,
                   %i[replay_group_target_size number_of_replay_processes] => :connect do |_t, args|
                     replay_group_target_size = args[:replay_group_target_size]&.to_i ||
                                                Sequent.configuration.replay_group_target_size&.to_i
                     number_of_replay_processes = args[:number_of_replay_processes]&.to_i ||
                                                  Sequent.configuration.number_of_replay_processes

                     replayer = Sequent::Migrations::ProjectorsReplayer.resume_from_database
                     replayer.perform_incremental_replay(replay_group_target_size:, number_of_replay_processes:)
                     show_replay_state(replayer.state)
                   end

              desc <<~EOS
                Optimizes and prepares the replayed tables for activation (VACUUM, CREATE INDEX, ANALYZE)

                Vacuums (or clusters, if there is a clustered index) the replayed tables and re-creates the query
                only indexes. Once this step is completed the replayed tables can go live.
              EOS
              task optimize: :connect do
                Sequent.logger.info('preparing replayed tables for activation')
                replayer = Sequent::Migrations::ProjectorsReplayer.resume_from_database
                replayer.prepare_for_activation!
                show_replay_state(replayer.state)
              end

              desc <<~EOS
                Performs replay of new event since last and atomically actives the replayed projector using the new tables

                Atomically replays any events since the last replay (temporarily blocking the projectors writing to the
                view schema) and moves the replayed tables into the view schema (the old view schema tables are moved to
                the archive schema). Once the tables have been moved the running system can write to the view schema
                again.
              EOS
              task golive: :connect do
                Sequent.logger.info('activating replayed projectors')
                replayer = Sequent::Migrations::ProjectorsReplayer.resume_from_database
                replayer.activate!
                show_replay_state(replayer.state)
                Sequent.logger.info('replayed projectors are now live (previous data saved in the archive schema)')
              end
            end
          end
        end
      end

      private

      # rubocop:disable Naming/MemoizedInstanceVariableName
      def ensure_sequent_env_set!
        @env ||= Sequent.env || fail('SEQUENT_ENV not set')
      end
      # rubocop:enable Naming/MemoizedInstanceVariableName

      def show_replay_state(replay_state)
        next_actions = case replay_state.state
                       when 'completed', 'aborted'
                         %w[prepare_initial]
                       when 'prepared_initial'
                         %w[initial abort]
                       when 'replaying_initial', 'replaying_increment'
                         %w[]
                       when 'replayed'
                         %w[increment prepare_completion abort]
                       when 'prepared_completion'
                         %w[increment complete abort]
                       when 'failed'
                         %w[abort]
                       end
        Sequent.logger.info(
          format(
            'replay state: %s at %s, continue at xact_id: %s, projectors: %s',
            replay_state.state,
            replay_state.updated_at,
            replay_state.continue_replay_at_xact_id || 0,
            replay_state.projectors.join(', '),
          ),
        )
        if next_actions.present?
          available_tasks = next_actions.map { |a| "sequent:projectors:replay:#{a}" }
          Sequent.logger.info("available tasks: #{available_tasks.join(', ')}")
        end
      end
    end
  end
end
