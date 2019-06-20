require 'active_record'
require 'rake'
require 'rake/tasklib'

require 'sequent/support'
require 'sequent/migrations/view_schema'

module Sequent
  module Rake
    class MigrationTasks < ::Rake::TaskLib
      include ::Rake::DSL

      def register_tasks!
        namespace :sequent do
          desc 'Rake task that runs before all sequent rake tasks. Hook applications can use to for instance run other rake tasks.'
          task :init

          namespace :db do

            desc 'Creates the database and initializes the event_store schema for the current env'
            task :create => ['sequent:init'] do
              ensure_rack_env_set!

              db_config = Sequent::Support::Database.read_config(@env)
              Sequent::Support::Database.create!(db_config)

              create_event_store(db_config)
            end

            desc 'Drops the database for the current env'
            task :drop, [:production] => ['sequent:init'] do |_t, args|
              ensure_rack_env_set!

              fail "Wont drop db in production unless you whitelist the environment as follows: rake sequent:db:drop[yes_drop_production]" if @env == 'production' && args[:production] != 'yes_drop_production'

              db_config = Sequent::Support::Database.read_config(@env)
              Sequent::Support::Database.drop!(db_config)
            end

            desc 'Creates the view schema for the current env'
            task :create_view_schema => ['sequent:init'] do
              ensure_rack_env_set!

              db_config = Sequent::Support::Database.read_config(@env)
              Sequent::Support::Database.establish_connection(db_config)
              Sequent::Migrations::ViewSchema.new(db_config: db_config).create_view_schema_if_not_exists
            end

            desc 'Creates the event_store schema for the current env'
            task :create_event_store => ['sequent:init'] do
              ensure_rack_env_set!
              db_config = Sequent::Support::Database.read_config(@env)
              create_event_store(db_config)
            end

            def create_event_store(db_config)
              event_store_schema = Sequent.configuration.event_store_schema_name
              sequent_schema = File.join(Sequent.configuration.database_config_directory, "#{event_store_schema}.rb")
              fail "File #{sequent_schema} does not exist. Check your Sequent configuration." unless File.exists?(sequent_schema)

              Sequent::Support::Database.establish_connection(db_config)
              fail "Schema #{event_store_schema} already exists in the database" if Sequent::Support::Database.schema_exists?(event_store_schema)

              Sequent::Support::Database.create_schema(event_store_schema)
              Sequent::Support::Database.with_schema_search_path(event_store_schema, db_config, @env) do
                load(sequent_schema)
              end
            end
          end

          namespace :migrate do
            desc 'Rake task that runs before all migrate rake tasks. Hook applications can use to for instance run other rake tasks.'
            task :init

            desc 'Prints the current version in the database'
            task :current_version => ['sequent:init', :init] do
              ensure_rack_env_set!

              Sequent::Support::Database.connect!(@env)

              puts "Current version in the database is: #{Sequent::Migrations::ViewSchema::Versions.maximum(:version)}"
            end

            desc 'Migrates the Projectors while the app is running. Call +sequent:migrate:offline+ after this successfully completed.'
            task :online => ['sequent:init', :init] do
              ensure_rack_env_set!

              db_config = Sequent::Support::Database.read_config(@env)
              view_schema = Sequent::Migrations::ViewSchema.new(db_config: db_config)

              view_schema.migrate_online
            end

            desc 'Migrates the events inserted while +online+ was running. It is expected +sequent:migrate:online+ ran first.'
            task :offline => ['sequent:init', :init] do
              ensure_rack_env_set!

              db_config = Sequent::Support::Database.read_config(@env)
              view_schema = Sequent::Migrations::ViewSchema.new(db_config: db_config)

              view_schema.migrate_offline
            end
          end

          namespace :snapshots do
            desc 'Rake task that runs before all snapshots rake tasks. Hook applications can use to for instance run other rake tasks.'
            task :init

            task :set_snapshot_threshold, [:aggregate_type,:threshold] => ['sequent:init', :init] do
              aggregate_type = args['aggregate_type']
              threshold = args['threshold']

              fail ArgumentError.new('usage rake sequent:snapshots:set_snapshot_threshold[AggregegateType,threshold]') unless aggregate_type
              fail ArgumentError.new('usage rake sequent:snapshots:set_snapshot_threshold[AggregegateType,threshold]') unless threshold

              execute "UPDATE #{Sequent.configuration.stream_record_class} SET snapshot_threshold = #{threshold.to_i} WHERE aggregate_type = '#{aggregate_type}'"
            end

            task :delete_all => ['sequent:init', :init] do
              result = Sequent::ApplicationRecord.connection.execute("DELETE FROM #{Sequent.configuration.event_record_class.table_name} WHERE event_type = 'Sequent::Core::SnapshotEvent'")
              Sequent.logger.info "Deleted #{result.cmd_tuples} aggregate snapshots from the event store"
            end
          end
        end
      end

      private
      def ensure_rack_env_set!
        @env ||= ENV['RACK_ENV'] || fail("RACK_ENV not set")
      end
    end
  end
end
