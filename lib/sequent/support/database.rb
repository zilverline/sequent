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

      def self.with_schema_search_path(search_path, db_config, env = ENV['RACK_ENV'])
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
        sql = "CREATE SCHEMA IF NOT EXISTS #{schema}"
        if user = ActiveRecord::Base.connection_config[:username]
          sql += " AUTHORIZATION #{user}"
        end
        ActiveRecord::Base.connection.execute(sql)
      end

      def drop_schema!(schema)
        ActiveRecord::Base.connection.execute(
          "DROP SCHEMA IF EXISTS #{schema} CASCADE"
        )
      end

      def migrate(migrations_path, verbose: true)
        ActiveRecord::Migration.verbose = verbose
        ActiveRecord::Migrator.migrate(migrations_path)
      end
    end
  end
end
