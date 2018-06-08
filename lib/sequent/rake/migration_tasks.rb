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

            desc 'Create the database for the current env'
            task :create => ['sequent:init'] do
              ensure_rack_env_set!
              sequent_schema = File.join(Sequent.configuration.database_config_directory, "#{Sequent.configuration.event_store_schema_name}.rb")

              fail "File #{sequent_schema} does not exist. Check your Sequent configuration." unless File.exists?(sequent_schema)

              db_config = Sequent::Support::Database.read_config(@env)
              Sequent::Support::Database.create!(db_config)

              Sequent::Support::Database.establish_connection(db_config)
              Sequent::Support::Database.create_schema(Sequent.configuration.event_store_schema_name)
              load(sequent_schema)
            end

            desc 'Drops the database for the current env'
            task :drop, [:production] => ['sequent:init'] do |_t, args|
              ensure_rack_env_set!

              fail "Wont drop db in production unless you whitelist the environment as follows: rake sequent:db:drop[production]" if @env == 'production' && args[:production] != 'production'

              db_config = Sequent::Support::Database.read_config(@env)
              Sequent::Support::Database.drop!(db_config)
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
        end
      end

      private
      def ensure_rack_env_set!
        @env ||= ENV['RACK_ENV'] || fail("RACK_ENV not set")
      end
    end
  end
end
