# frozen_string_literal: true

module Sequent
  module Migrations
    class SequentSchema
      FAIL_IF_EXISTS = ->(schema_name) { fail "Schema #{schema_name} already exists in the database" }

      class << self
        #
        # Creates the sequent schema if it does not exist yet
        #
        # @param env [String] The environment used to setup database connection
        # @param fail_if_exists [Boolean] When true fails if the schema exists, otherwise just return.
        def create_sequent_schema_if_not_exists(env:, fail_if_exists: true)
          fail ArgumentError, 'env is required' if env.blank?

          db_config = Sequent::Support::Database.read_config(env)

          Sequent::Support::Database.establish_connection(db_config)

          event_store_schema = Sequent.configuration.event_store_schema_name
          schema_exists = Sequent::Support::Database.schema_exists?(event_store_schema)

          FAIL_IF_EXISTS.call(event_store_schema) if schema_exists && fail_if_exists
          return if schema_exists

          sequent_schema = File.join(Sequent.configuration.database_schema_directory, "#{event_store_schema}.rb")
          unless File.exist?(sequent_schema)
            fail "File '#{sequent_schema}' does not exist. Check your Sequent configuration."
          end

          Sequent::Support::Database.create_schema(event_store_schema)
          Sequent::Support::Database.with_schema_search_path(event_store_schema, db_config, env) do
            load(sequent_schema)
          end
        end
      end
    end
  end
end
