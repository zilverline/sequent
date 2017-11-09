require_relative 'core/event_store'
require_relative 'core/command_service'
require_relative 'core/transactions/no_transactions'
require_relative 'core/aggregate_repository'

module Sequent
  class Configuration
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
    end
  end
end
