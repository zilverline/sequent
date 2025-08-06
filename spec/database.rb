# frozen_string_literal: true

require 'active_record'
require 'active_support/hash_with_indifferent_access'

module Database
  class << self
    def test_config(database_name: 'sequent_spec_db')
      ActiveSupport::HashWithIndifferentAccess.new(
        {
          adapter: 'postgresql',
          host: 'localhost',
          username: 'sequent',
          password: 'sequent',
          database: database_name,
          schema_search_path: "public,#{Sequent.configuration.view_schema_name}," \
                              "#{Sequent.configuration.event_store_schema_name}",
          advisory_locks: false,
        },
      ).stringify_keys
    end

    def establish_connection(config = test_config)
      Sequent::Support::Database.establish_connection(config)
    end
  end
end
