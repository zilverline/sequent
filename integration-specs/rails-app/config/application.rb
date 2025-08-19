# frozen_string_literal: true

require_relative 'boot'

require 'rails/all'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module RailsApp
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.0

    config.middleware.use Sequent::Util::Web::ClearCache

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    #####################################################################
    # SEQUENT
    #####################################################################
    config.active_record.schema_format = :sql
    config.active_record.dump_schemas = nil
    ActiveRecord::Tasks::DatabaseTasks.structure_dump_flags = %W[
      --exclude-schema=#{Sequent.configuration.replay_schema_name}
      --exclude-schema=#{Sequent.configuration.archive_schema_name}
    ]
    #####################################################################
    # END SEQUENT
    #####################################################################
  end
end
