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
      attr_reader :db_config

      def self.connect!(env)
        db_config = read_config(env)
        establish_connection(db_config)
      end

      def self.read_config(env)
        fail ArgumentError, 'env is mandatory' unless env

        database_yml = File.join(Sequent.configuration.database_config_directory, 'database.yml')
        config = YAML.safe_load(ERB.new(File.read(database_yml)).result, aliases: true)[env]
        ActiveRecord::Base.configurations.resolve(config).configuration_hash.with_indifferent_access
      end

      def self.create!(db_config)
        establish_connection(db_config, {database: 'postgres'})
        ActiveRecord::Base.connection.create_database(get_db_config_attribute(db_config, :database))
      end

      def self.drop!(db_config)
        establish_connection(db_config, {database: 'postgres'})
        ActiveRecord::Base.connection.drop_database(get_db_config_attribute(db_config, :database))
      end

      def self.get_db_config_attribute(db_config, attribute)
        if Sequent.configuration.can_use_multiple_databases?
          db_config[Sequent.configuration.primary_database_key][attribute]
        else
          db_config[attribute]
        end
      end

      def self.establish_connection(db_config, db_config_overrides = {})
        if Sequent.configuration.can_use_multiple_databases?
          db_config = db_config.deep_merge(
            Sequent.configuration.primary_database_key => db_config_overrides,
          ).stringify_keys
          ActiveRecord::Base.configurations = db_config.stringify_keys
          ActiveRecord::Base.connects_to database: {
            Sequent.configuration.primary_database_role => Sequent.configuration.primary_database_key,
          }
        else
          db_config = db_config.merge(db_config_overrides)
          ActiveRecord::Base.establish_connection(db_config)
        end
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
        execute_sql "DROP SCHEMA if exists #{schema_name} cascade"
      end

      def self.with_schema_search_path(search_path, db_config, env = ENV['SEQUENT_ENV'])
        fail ArgumentError, 'env is required' unless env

        disconnect!

        establish_connection(db_config, {schema_search_path: search_path})
        yield
      ensure
        disconnect!
        establish_connection(db_config)
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
