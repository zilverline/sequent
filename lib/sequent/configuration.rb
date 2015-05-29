require_relative 'core/event_store'
require_relative 'core/command_service'
require_relative 'core/transactions/no_transactions'
require_relative 'core/aggregate_repository'

module Sequent
  class Configuration
    attr_reader :aggregate_repository

    attr_accessor :event_store,
                  :command_service,
                  :event_record_class,
                  :stream_record_class,
                  :snapshot_event_class,
                  :transaction_provider

    attr_accessor :command_handlers,
                  :command_filters

    attr_accessor :event_handlers

    def self.instance
      @instance ||= new
    end

    def self.reset
      @instance = new
    end

    def initialize
      self.command_handlers = []
      self.command_filters = []
      self.event_handlers = []

      self.event_store = Sequent::Core::EventStore.new(self)
      self.command_service = Sequent::Core::CommandService.new(self)
      self.event_record_class = Sequent::Core::EventRecord
      self.stream_record_class = Sequent::Core::StreamRecord
      self.snapshot_event_class = Sequent::Core::SnapshotEvent
      self.transaction_provider = Sequent::Core::Transactions::NoTransactions.new
    end

    def event_store=(event_store)
      @event_store = event_store
      @aggregate_repository = Sequent::Core::AggregateRepository.new(event_store)
      self.command_handlers.each { |c| c.repository = @aggregate_repository }
    end
  end
end
