# frozen_string_literal: true

require 'erb'
require 'active_support/hash_with_indifferent_access'

module Sequent
  module Support
    # Offers support operations for a postgres database.
    #
    # Class methods do establish their own database connections (and therefore
    # take in a database configuration). Instance methods assume that a database
    # connection yet is established.
    class Database
      include ActiveRecord::Tasks

      def self.connect!(env)
        ActiveRecord::Base.establish_connection(env&.to_sym)
      end

      def self.read_database_config(env)
        fail ArgumentError, 'env is mandatory' unless env

        ActiveRecord::Base.configurations.find_db_config(env)
      end

      def self.read_config(env) = read_database_config(env)

      def self.create!(db_config)
        DatabaseTasks.create(db_config)
      end

      def self.drop!(db_config)
        DatabaseTasks.drop(db_config)
      end

      def self.establish_connection(db_config_or_env = Sequent.env&.to_sym)
        ActiveRecord::Base.establish_connection(db_config_or_env)
      end

      def self.disconnect!
        ActiveRecord::Base.connection_pool.disconnect!
      end

      def self.execute_sql(sql)
        ActiveRecord::Base.connection.execute(sql)
      end

      def self.create_schema(schema)
        sql = "CREATE SCHEMA IF NOT EXISTS #{schema}"
        user = configuration_hash[:username]
        sql += %( AUTHORIZATION "#{user}") if user
        execute_sql(sql)
      end

      def self.drop_schema!(schema_name)
        execute_sql "DROP SCHEMA IF EXISTS #{schema_name} CASCADE"
      end

      def self.with_search_path(search_path)
        old_search_path = ActiveRecord::Base.connection.select_value("SELECT current_setting('search_path')")
        begin
          ActiveRecord::Base.connection.exec_update("SET search_path TO #{search_path}", 'with_search_path')
          yield
        ensure
          ActiveRecord::Base.connection.exec_update("SET search_path TO #{old_search_path}", 'with_search_path')
        end
      end

      def self.schema_exists?(schema, event_records_table = nil)
        schema_exists = ActiveRecord::Base.connection.exec_query(
          'SELECT 1 FROM information_schema.schemata WHERE schema_name LIKE $1',
          'schema_exists?',
          [schema],
        ).count == 1

        # The ActiveRecord 7.1 schema_dumper.rb now also adds `create_schema` statements for any schema that
        # is not named `public`, and in this case the schema may already be created so we check for the
        # existence of the `event_records` table (or view) as well.
        return schema_exists unless event_records_table

        ActiveRecord::Base.connection.exec_query(
          'SELECT 1 FROM information_schema.tables WHERE table_schema LIKE $1 AND table_name LIKE $2',
          'schema_exists?',
          [schema, event_records_table],
        ).count == 1
      end

      def self.configuration_hash
        ActiveRecord::Base.connection_db_config.configuration_hash
      end

      def schema_exists?(schema, event_records_table = nil)
        self.class.schema_exists?(schema, event_records_table)
      end

      def create_schema!(schema)
        self.class.create_schema(schema)
      end

      def drop_schema!(schema)
        self.class.drop_schema!(schema)
      end

      def execute_sql(sql)
        self.class.execute_sql(sql)
      end
    end
  end
end
