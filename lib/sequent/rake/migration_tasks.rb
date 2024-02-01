# frozen_string_literal: true

require 'active_record'
require 'rake'
require 'rake/tasklib'

require 'sequent/support'
require 'sequent/migrations/view_schema'
require 'sequent/migrations/sequent_schema'

module Sequent
  module Rake
    class MigrationTasks < ::Rake::TaskLib
      include ::Rake::DSL

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

          desc 'Creates sequent view schema if not exists and runs internal migrations'
          task create_and_migrate_sequent_view_schema: ['sequent:init', :init] do
            ensure_sequent_env_set!
            Sequent::Migrations::ViewSchema.create_view_schema_if_not_exists(env: @env)
          end

          namespace :db do
            desc 'Creates the database and initializes the event_store schema for the current env'
            task create: ['sequent:init'] do
              ensure_sequent_env_set!

              db_config = Sequent::Support::Database.read_config(@env)
              Sequent::Support::Database.create!(db_config)

              Sequent::Migrations::SequentSchema.create_sequent_schema_if_not_exists(env: @env, fail_if_exists: true)
            end

            desc 'Drops the database for the current env'
            task :drop, [:production] => ['sequent:init'] do |_t, args|
              ensure_sequent_env_set!

              if @env == 'production' && args[:production] != 'yes_drop_production'
                fail <<~OES
                  Wont drop db in production unless you whitelist the environment as follows: rake sequent:db:drop[yes_drop_production]
                OES
              end

              db_config = Sequent::Support::Database.read_config(@env)
              Sequent::Support::Database.drop!(db_config)
            end

            desc 'Creates the view schema for the current env'
            task create_view_schema: ['sequent:init'] do
              ensure_sequent_env_set!

              Sequent::Migrations::ViewSchema.create_view_schema_if_not_exists(env: @env)
            end

            desc 'Creates the event_store schema for the current env'
            task create_event_store: ['sequent:init'] do
              ensure_sequent_env_set!
              Sequent::Migrations::SequentSchema.create_sequent_schema_if_not_exists(env: @env, fail_if_exists: true)
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

            desc 'Prints the current version in the database'
            task current_version: [:create_and_migrate_sequent_view_schema] do
              puts "Current version in the database is: #{Sequent::Migrations::Versions.current_version}"
            end

            desc 'Returns whether a migration is currently running'
            task check_running_migrations: [:create_and_migrate_sequent_view_schema] do
              if Sequent::Migrations::Versions.running.any?
                puts "Migration is running, current version: #{Sequent::Migrations::Versions.current_version}, " /
                     "target version #{Sequent::Migrations::Versions.version_currently_migrating}"
              else
                puts 'No running migrations'
              end
            end

            desc 'Returns whether a migration is pending'
            task check_pending_migrations: [:create_and_migrate_sequent_view_schema] do
              if Sequent.new_version != Sequent::Migrations::Versions.current_version
                puts "Migration is pending, current version: #{Sequent::Migrations::Versions.current_version}, " /
                     "pending version: #{Sequent.new_version}"
              else
                puts 'No pending migrations'
              end
            end

            desc <<~EOS
              Migrates the Projectors while the app is running. Call +sequent:migrate:offline+ after this successfully completed.
            EOS
            task online: ['sequent:init', :init] do
              ensure_sequent_env_set!

              db_config = Sequent::Support::Database.read_config(@env)
              view_schema = Sequent::Migrations::ViewSchema.new(db_config: db_config)

              view_schema.migrate_online
            end

            desc <<~EOS
              Migrates the events inserted while +online+ was running. It is expected +sequent:migrate:online+ ran first.
            EOS
            task offline: ['sequent:init', :init] do
              ensure_sequent_env_set!

              db_config = Sequent::Support::Database.read_config(@env)
              view_schema = Sequent::Migrations::ViewSchema.new(db_config: db_config)

              view_schema.migrate_offline
            end

            desc <<~EOS
              Runs the projectors in replay mode without making any changes to the database, useful for (performance) testing against real data.

              Pass a regular expression as parameter to select the projectors to run, otherwise all projectors are selected.
            EOS
            task :dryrun, %i[regex group_exponent limit offset] => ['sequent:init', :init] do |_task, args|
              ensure_sequent_env_set!

              db_config = Sequent::Support::Database.read_config(@env)
              view_schema = Sequent::Migrations::ViewSchema.new(db_config: db_config)

              view_schema.migrate_dryrun(
                regex: args[:regex],
                group_exponent: (args[:group_exponent] || 3).to_i,
                limit: args[:limit]&.to_i,
                offset: args[:offset]&.to_i,
              )
            end
          end

          namespace :snapshots do
            desc <<~EOS
              Rake task that runs before all snapshots rake tasks. Hook applications can use to for instance run other rake tasks.
            EOS
            task :init

            task :set_snapshot_threshold, %i[aggregate_type threshold] => ['sequent:init', :init] do |_t, args|
              aggregate_type = args['aggregate_type']
              threshold = args['threshold']

              unless aggregate_type
                fail ArgumentError,
                     'usage rake sequent:snapshots:set_snapshot_threshold[AggregegateType,threshold]'
              end
              unless threshold
                fail ArgumentError,
                     'usage rake sequent:snapshots:set_snapshot_threshold[AggregegateType,threshold]'
              end

              execute <<~EOS
                UPDATE #{Sequent.configuration.stream_record_class} SET snapshot_threshold = #{threshold.to_i} WHERE aggregate_type = '#{aggregate_type}'
              EOS
            end

            task delete_all: ['sequent:init', :init] do
              result = Sequent::ApplicationRecord
                .connection
                .execute(<<~EOS)
                  DELETE FROM #{Sequent.configuration.event_record_class.table_name} WHERE event_type = 'Sequent::Core::SnapshotEvent'
                EOS
              Sequent.logger.info "Deleted #{result.cmd_tuples} aggregate snapshots from the event store"
            end
          end
        end
      end

      private

      # rubocop:disable Naming/MemoizedInstanceVariableName
      def ensure_sequent_env_set!
        @env ||= ENV['SEQUENT_ENV'] || fail('SEQUENT_ENV not set')
      end
      # rubocop:enable Naming/MemoizedInstanceVariableName
    end
  end
end
