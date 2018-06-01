require 'active_record'
require 'rake'
require 'rake/tasklib'

require 'sequent/support'

module Sequent
  module Rake
    class MigrationTasks < ::Rake::TaskLib
      include ::Rake::DSL

      def register_tasks!
        namespace :sequent do
          namespace :db do

            desc 'Create the database for the current env'
            task :create do
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
            task :drop, [:production] do |_t, args|
              ensure_rack_env_set!

              fail "Wont drop db in production unless you whitelist the environment as follows: rake sequent:db:drop[production]" if @env == 'production' && args[:production] != 'production'

              db_config = Sequent::Support::Database.read_config(@env)
              Sequent::Support::Database.drop!(db_config)
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
