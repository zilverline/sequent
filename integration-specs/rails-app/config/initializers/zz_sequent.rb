# frozen_string_literal: true

require 'sequent'

require_relative '../../db/sequent_migrations'

Rails.application.reloader.to_prepare do
  Sequent.configure do |config|
    config.enable_autoregistration = true
    config.event_store_cache_event_types = !Rails.env.development?

    config.migrations_class_name = 'SequentMigrations'

    config.database_config_directory = 'config'

    # this is the location of your sql files for your view_schema
    config.migration_sql_files_directory = 'db/sequent'
    config.logger = Logger.new(STDOUT)
    config.logger.level = Logger::DEBUG
    config.logger.formatter = proc do |severity, datetime, _progname, msg|
      "#{severity[0]} [sequent] #{datetime.strftime('%Y%m%d %H:%M:%S')} - #{msg}\n"
    end
  end
end
