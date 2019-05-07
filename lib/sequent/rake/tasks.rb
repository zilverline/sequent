require 'active_record'
require 'rake'
require 'rake/tasklib'

require 'sequent/support'

module Sequent
  module Rake
    class Tasks < ::Rake::TaskLib
      include ::Rake::DSL

      DEFAULT_OPTIONS = {
        migrations_path: 'db/migrate',
        event_store_schema: 'public'
      }

      attr_reader :options

      def initialize(options)
        @options = DEFAULT_OPTIONS.merge(options)
      end

      def display_deprecation_warning
        warn '[DEPRECATED] Sequent::Rake::Tasks is deprecated. Please use Sequent::Rake::MigrationTasks tasks instead.'
      end

      def register!
        display_deprecation_warning

        register_db_tasks!
        register_view_schema_tasks!
      end

      def register_db_tasks!
        namespace :db do
          desc 'Create the database'
          task :create do
            display_deprecation_warning

            current_environments.each do |env|
              env_db = db_config(env)
              puts "Create database #{env_db['database']}"
              Sequent::Support::Database.create!(env_db)
            end
          end

          desc 'Drop the database'
          task :drop do
            display_deprecation_warning

            current_environments.each do |env|
              env_db = db_config(env)
              puts "Drop database #{env_db['database']}"
              Sequent::Support::Database.drop!(env_db)
            end
          end

          task :establish_connection do
            env_db = db_config(options.fetch(:environment))
            ActiveRecord::Base.establish_connection(env_db)
          end

          desc 'Migrate the database'
          task migrate: :establish_connection do
            display_deprecation_warning

            database.create_schema!(options.fetch(:event_store_schema))
            database.migrate(options.fetch(:migrations_path))
          end
        end
      end

      def register_view_schema_tasks!
        namespace :view_schema do
          desc 'Build the view schema'
          task build: :'db:establish_connection' do
            display_deprecation_warning

            if database.schema_exists?(view_projection.schema_name)
              puts "View version #{view_projection.version} already exists; no need to build it"
            else
              database.create_schema!(view_projection.schema_name)
              view_projection.build!
            end
          end

          desc 'Drop the view schema'
          task drop: :'db:establish_connection' do
            display_deprecation_warning

            database.drop_schema!(view_projection.schema_name)
          end
        end
      end

      private

      def current_environments
        environment = options.fetch(:environment)
        envs = [environment]
        envs << 'test' if environment == 'development'
        envs
      end

      def database
        @database ||= Sequent::Support::Database.new
      end

      def db_config(environment)
        options.fetch(:db_config_supplier)[environment] or fail "No database config for #{environment}"
      end

      def view_projection
        options.fetch(:view_projection)
      end
    end
  end
end
