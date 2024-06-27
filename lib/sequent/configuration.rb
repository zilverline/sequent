# frozen_string_literal: true

require_relative 'core/event_store'
require_relative 'core/command_service'
require_relative 'core/transactions/no_transactions'
require_relative 'core/aggregate_repository'
require_relative 'core/persistors/active_record_persistor'
require 'logger'

module Sequent
  class Configuration
    DEFAULT_VERSIONS_TABLE_NAME = 'sequent_versions'

    DEFAULT_MIGRATION_SQL_FILES_DIRECTORY = 'db/tables'
    DEFAULT_DATABASE_CONFIG_DIRECTORY = 'db'
    DEFAULT_DATABASE_SCHEMA_DIRECTORY = 'db'

    DEFAULT_VIEW_SCHEMA_NAME = 'view_schema'
    DEFAULT_EVENT_STORE_SCHEMA_NAME = 'sequent_schema'

    MIGRATIONS_CLASS_NAME = 'Sequent::Migrations::Projectors'

    DEFAULT_NUMBER_OF_REPLAY_PROCESSES = 4
    DEFAULT_REPLAY_GROUP_TARGET_SIZE = 250_000

    DEFAULT_OFFLINE_REPLAY_PERSISTOR_CLASS = Sequent::Core::Persistors::ActiveRecordPersistor
    DEFAULT_ONLINE_REPLAY_PERSISTOR_CLASS = Sequent::Core::Persistors::ActiveRecordPersistor

    DEFAULT_EVENT_RECORD_HOOKS_CLASS = Sequent::Core::EventRecordHooks

    DEFAULT_STRICT_CHECK_ATTRIBUTES_ON_APPLY_EVENTS = false

    DEFAULT_ERROR_LOCALE_RESOLVER = -> { I18n.locale || :en }

    DEFAULT_TIME_PRECISION = ActiveSupport::JSON::Encoding.time_precision

    attr_accessor :aggregate_repository,
                  :event_store,
                  :command_service,
                  :event_record_class,
                  :snapshot_record_class,
                  :stream_record_class,
                  :transaction_provider,
                  :event_publisher,
                  :event_record_hooks_class,
                  :command_handlers,
                  :command_filters,
                  :command_middleware,
                  :event_handlers,
                  :uuid_generator,
                  :disable_event_handlers,
                  :logger,
                  :error_locale_resolver,
                  :migration_sql_files_directory,
                  :view_schema_name,
                  :offline_replay_persistor_class,
                  :online_replay_persistor_class,
                  :number_of_replay_processes,
                  :replay_group_target_size,
                  :database_config_directory,
                  :database_schema_directory,
                  :event_store_schema_name,
                  :strict_check_attributes_on_apply_events,
                  :enable_multiple_database_support,
                  :primary_database_role,
                  :primary_database_key,
                  :time_precision,
                  :enable_autoregistration

    attr_reader :migrations_class_name,
                :versions_table_name

    def self.instance
      @instance ||= new
    end

    # Create a new instance of Configuration
    def self.reset
      @instance = new
    end

    # Restore the given Configuration
    # @param configuration [Sequent::Configuration]
    def self.restore(configuration)
      @instance = configuration
    end

    def initialize
      self.command_handlers = []
      self.command_filters = []
      self.event_handlers = []
      self.command_middleware = Sequent::Core::Middleware::Chain.new

      self.aggregate_repository = Sequent::Core::AggregateRepository.new
      self.event_store = Sequent::Core::EventStore.new
      self.command_service = Sequent::Core::CommandService.new
      self.event_record_class = Sequent::Core::EventRecord
      self.snapshot_record_class = Sequent::Core::SnapshotRecord
      self.stream_record_class = Sequent::Core::StreamRecord
      self.transaction_provider = Sequent::Core::Transactions::ActiveRecordTransactionProvider.new
      self.uuid_generator = Sequent::Core::RandomUuidGenerator
      self.event_publisher = Sequent::Core::EventPublisher.new
      self.disable_event_handlers = false
      self.versions_table_name = DEFAULT_VERSIONS_TABLE_NAME
      self.migration_sql_files_directory = DEFAULT_MIGRATION_SQL_FILES_DIRECTORY
      self.view_schema_name = DEFAULT_VIEW_SCHEMA_NAME
      self.event_store_schema_name = DEFAULT_EVENT_STORE_SCHEMA_NAME
      self.migrations_class_name = MIGRATIONS_CLASS_NAME
      self.number_of_replay_processes = DEFAULT_NUMBER_OF_REPLAY_PROCESSES
      self.replay_group_target_size = DEFAULT_REPLAY_GROUP_TARGET_SIZE

      self.event_record_hooks_class = DEFAULT_EVENT_RECORD_HOOKS_CLASS

      self.offline_replay_persistor_class = DEFAULT_OFFLINE_REPLAY_PERSISTOR_CLASS
      self.online_replay_persistor_class = DEFAULT_ONLINE_REPLAY_PERSISTOR_CLASS
      self.database_config_directory = DEFAULT_DATABASE_CONFIG_DIRECTORY
      self.database_schema_directory = DEFAULT_DATABASE_SCHEMA_DIRECTORY
      self.strict_check_attributes_on_apply_events = DEFAULT_STRICT_CHECK_ATTRIBUTES_ON_APPLY_EVENTS

      self.logger = Logger.new(STDOUT).tap { |l| l.level = Logger::INFO }
      self.error_locale_resolver = DEFAULT_ERROR_LOCALE_RESOLVER

      self.enable_multiple_database_support = false
      self.primary_database_role = :writing
      self.primary_database_key = :primary

      self.time_precision = DEFAULT_TIME_PRECISION

      self.enable_autoregistration = false
    end

    def can_use_multiple_databases?
      enable_multiple_database_support
    end

    def versions_table_name=(table_name)
      fail ArgumentError, 'table_name can not be nil' unless table_name

      @versions_table_name = table_name
      Sequent::Migrations::Versions.table_name = table_name
    end

    def migrations_class_name=(class_name)
      migration_class = Class.const_get(class_name)
      unless migration_class <= Sequent::Migrations::Projectors
        fail ArgumentError, "#{migration_class} must extend Sequent::Migrations::Projectors"
      end

      @migrations_class_name = class_name
    end

    # @!visibility private
    def autoregister!
      return unless enable_autoregistration

      # Only autoregister the AggregateSnapshotter if the autoregistration is enabled
      Sequent::Core::AggregateSnapshotter.skip_autoregister = false

      autoload_if_in_rails

      self.class.instance.command_handlers ||= []
      for_each_autoregisterable_descenant_of(Sequent::CommandHandler) do |command_handler_class|
        if Sequent.logger.debug?
          Sequent.logger.debug("[Configuration] Autoregistering CommandHandler #{command_handler_class}")
        end
        self.class.instance.command_handlers << command_handler_class.new
      end

      self.class.instance.event_handlers ||= []
      for_each_autoregisterable_descenant_of(Sequent::Projector) do |projector_class|
        Sequent.logger.debug("[Configuration] Autoregistering Projector #{projector_class}") if Sequent.logger.debug?
        self.class.instance.event_handlers << projector_class.new
      end

      for_each_autoregisterable_descenant_of(Sequent::Workflow) do |workflow_class|
        Sequent.logger.debug("[Configuration] Autoregistering Workflow #{workflow_class}") if Sequent.logger.debug?
        self.class.instance.event_handlers << workflow_class.new
      end

      self.class.instance.command_handlers.map(&:class).tally.each do |(clazz, count)|
        if count > 1
          fail "CommandHandler #{clazz} is registered #{count} times. A CommandHandler can only be registered once"
        end
      end

      self.class.instance.event_handlers.map(&:class).tally.each do |(clazz, count)|
        if count > 1
          fail "EventHandler #{clazz} is registered #{count} times. An EventHandler can only be registered once"
        end
      end
    end

    private

    def autoload_if_in_rails
      Rails.autoloaders.main.eager_load(force: true) if defined?(Rails) && Rails.respond_to?(:autoloaders)
    end

    def for_each_autoregisterable_descenant_of(clazz, &block)
      clazz
        .descendants
        .reject(&:abstract_class)
        .reject(&:skip_autoregister)
        .each(&block)
    end
  end
end
