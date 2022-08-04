# frozen_string_literal: true

require 'active_record'
require 'active_support/hash_with_indifferent_access'

module Database
  def self.test_config
    if Sequent.configuration.can_use_multiple_databases?
      return ActiveSupport::HashWithIndifferentAccess.new(
        {
          Sequent.configuration.primary_database_key => {
            adapter: 'postgresql',
            host: 'localhost',
            username: 'sequent',
            password: 'sequent',
            database: 'sequent_spec_db',
            schema_search_path: "#{Sequent.configuration.view_schema_name},"\
                            "#{Sequent.configuration.event_store_schema_name},public",
            advisory_locks: false,
          },
        },
      ).stringify_keys
    end
    ActiveSupport::HashWithIndifferentAccess.new(
      {
        adapter: 'postgresql',
        host: 'localhost',
        username: 'sequent',
        password: 'sequent',
        database: 'sequent_spec_db',
        schema_search_path: "#{Sequent.configuration.view_schema_name},"\
                            "#{Sequent.configuration.event_store_schema_name},public",
        advisory_locks: false,
      },
    ).stringify_keys
  end

  def self.establish_connection(config = test_config)
    Sequent::Support::Database.establish_connection(config)
  end
end
