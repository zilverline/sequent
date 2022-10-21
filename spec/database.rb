# frozen_string_literal: true

require 'active_record'
require 'active_support/hash_with_indifferent_access'

module Database
  class << self
    def write_database_yml_for_test(env: 'test', database_name: 'sequent_spec_db')
      FileUtils.mkdir_p(Sequent.configuration.database_config_directory)
      database_yml = File.join(Sequent.configuration.database_config_directory, 'database.yml')
      if Sequent.configuration.enable_multiple_database_support
        db_config = {
          Sequent.configuration.primary_database_key.to_s =>
            test_config(database_name: database_name)[Sequent.configuration.primary_database_key.to_s].to_h,
        }
        File.write(database_yml, {env => db_config.to_h}.to_yaml)
      else
        File.write(database_yml, {env => test_config(database_name: database_name).to_h}.to_yaml)
      end
    end

    def test_config(database_name: 'sequent_spec_db')
      if Sequent.configuration.can_use_multiple_databases?
        return ActiveSupport::HashWithIndifferentAccess.new(
          {
            Sequent.configuration.primary_database_key => {
              adapter: 'postgresql',
              host: 'localhost',
              username: 'sequent',
              password: 'sequent',
              database: database_name,
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
          database: database_name,
          schema_search_path: "#{Sequent.configuration.view_schema_name},"\
                              "#{Sequent.configuration.event_store_schema_name},public",
          advisory_locks: false,
        },
      ).stringify_keys
    end

    def establish_connection(config = test_config)
      Sequent::Support::Database.establish_connection(config)
    end
  end
end
