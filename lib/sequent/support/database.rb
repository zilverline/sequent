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
        fail ArgumentError.new("env is mandatory") unless env

        database_yml = File.join(Sequent.configuration.database_config_directory, 'database.yml')
        YAML.load(ERB.new(File.read(database_yml)).result)[env]
      end

      def self.create!(db_config)
        ActiveRecord::Base.establish_connection(db_config.merge('database' => 'postgres'))
        ActiveRecord::Base.connection.create_database(db_config['database'])
      end

      def self.drop!(db_config)
        ActiveRecord::Base.establish_connection(db_config.merge('database' => 'postgres'))
        ActiveRecord::Base.connection.drop_database(db_config['database'])
      end

      def self.establish_connection(db_config)
        ActiveRecord::Base.establish_connection(db_config)
      end

      def self.disconnect!
        ActiveRecord::Base.connection_pool.disconnect!
      end

      def self.execute_sql(sql)
        ActiveRecord::Base.connection.execute(sql)
      end

      def self.create_schema(schema)
        sql = "CREATE SCHEMA IF NOT EXISTS #{schema}"
        if user = ActiveRecord::Base.connection_config[:username]
          sql += " AUTHORIZATION #{user}"
        end
        execute_sql(sql)
      end

      def self.drop_schema!(schema_name)
        execute_sql "DROP SCHEMA if exists #{schema_name} cascade"
      end

      def self.with_schema_search_path(search_path, db_config, env = ENV['RACK_ENV'])
        fail ArgumentError.new("env is required") unless env

        disconnect!
        original_search_paths = db_config['schema_search_path'].dup
        ActiveRecord::Base.configurations[env.to_s] = ActiveSupport::HashWithIndifferentAccess.new(db_config).stringify_keys
        db_config['schema_search_path'] = search_path
        ActiveRecord::Base.establish_connection db_config

        yield

      ensure
        disconnect!
        db_config['schema_search_path'] = original_search_paths
        establish_connection(db_config)
      end

      def schema_exists?(schema)
        ActiveRecord::Base.connection.execute(
          "SELECT schema_name FROM information_schema.schemata WHERE schema_name like '#{schema}'"
        ).count == 1
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

      def migrate(migrations_path, verbose: true)
        ActiveRecord::Migration.verbose = verbose
        ActiveRecord::Migrator.migrate(migrations_path)
      end
    end
  end
end
