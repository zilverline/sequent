require_relative 'core/event_store'
require_relative 'core/command_service'
require_relative 'core/transactions/no_transactions'
require_relative 'core/aggregate_repository'
require_relative 'core/record_sessions/active_record_session'
require 'logger'

module Sequent
  class Configuration

    DEFAULT_VERSIONS_TABLE_NAME = 'sequent_versions'
    DEFAULT_REPLAYED_IDS_TABLE_NAME = 'sequent_replayed_ids'
    DEFAULT_MIGRATION_SQL_FILES_DIRECTORY = 'db/tables'
    DEFAULT_VIEW_SCHEMA_NAME = 'view_schema'
    MIGRATIONS_CLASS_NAME = 'Sequent::ViewSchema::Migrations'
    DEFAULT_REPLAY_EVENTS_SESSION_CLASS = Sequent::Core::RecordSessions::ActiveRecordSession
    DEFAULT_NUMBER_OF_REPLAY_PROCESSES = 4

    attr_accessor :aggregate_repository

    attr_accessor :event_store,
                  :command_service,
                  :event_record_class,
                  :stream_record_class,
                  :snapshot_event_class,
                  :transaction_provider,
                  :event_publisher

    attr_accessor :command_handlers,
                  :command_filters

    attr_accessor :event_handlers

    attr_accessor :uuid_generator

    attr_accessor :disable_event_handlers

    attr_accessor :logger

    attr_accessor :migration_sql_files_directory,
                  :view_schema_name,
                  :replay_events_session_class,
                  :number_of_replay_processes

    attr_reader :migrations_class_name,
                :versions_table_name,
                :replayed_ids_table_name

    def self.instance
      @instance ||= new
    end

    def self.reset
      @instance = new
    end

    def self.restore(configuration)
      @instance = configuration
    end

    def initialize
      self.command_handlers = []
      self.command_filters = []
      self.event_handlers = []

      self.aggregate_repository = Sequent::Core::AggregateRepository.new
      self.event_store = Sequent::Core::EventStore.new
      self.command_service = Sequent::Core::CommandService.new
      self.event_record_class = Sequent::Core::EventRecord
      self.stream_record_class = Sequent::Core::StreamRecord
      self.snapshot_event_class = Sequent::Core::SnapshotEvent
      self.transaction_provider = Sequent::Core::Transactions::NoTransactions.new
      self.uuid_generator = Sequent::Core::RandomUuidGenerator
      self.event_publisher = Sequent::Core::EventPublisher.new
      self.disable_event_handlers = false
      self.versions_table_name = DEFAULT_VERSIONS_TABLE_NAME
      self.replayed_ids_table_name = DEFAULT_REPLAYED_IDS_TABLE_NAME
      self.migration_sql_files_directory = DEFAULT_MIGRATION_SQL_FILES_DIRECTORY
      self.view_schema_name = DEFAULT_VIEW_SCHEMA_NAME
      self.migrations_class_name = MIGRATIONS_CLASS_NAME
      self.replay_events_session_class = DEFAULT_REPLAY_EVENTS_SESSION_CLASS
      self.number_of_replay_processes = DEFAULT_NUMBER_OF_REPLAY_PROCESSES
      self.logger = Logger.new(STDOUT).tap {|l| l.level = Logger::INFO }
    end

    def replayed_ids_table_name=(table_name)
      fail ArgumentError.new('table_name can not be nil') unless table_name

      @replayed_ids_table_name = table_name
      Sequent::ViewSchema::ReplayedIds.table_name = table_name
    end

    def versions_table_name=(table_name)
      fail ArgumentError.new('table_name can not be nil') unless table_name

      @versions_table_name = table_name
      Sequent::ViewSchema::Versions.table_name = table_name
    end

    def migrations_class_name=(class_name)
      migration_class = Class.const_get(class_name)
      fail ArgumentError.new("#{migration_class} must respond_to class method versions") unless migration_class.respond_to?(:versions)
      fail ArgumentError.new("#{migration_class} must respond_to class method version") unless migration_class.respond_to?(:version)
      fail ArgumentError.new("#{migration_class} must extend Sequent::ViewSchema::Migrations") unless migration_class <= Sequent::ViewSchema::Migrations
      @migrations_class_name = class_name
    end

  end
end
