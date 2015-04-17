require_relative 'core/event_store'
require_relative 'core/command_service'
require_relative 'core/transactions/no_transactions'
require_relative 'core/aggregate_repository'

module Sequent
  class Configuration
    attr_accessor :event_store,
      :command_service,
      :aggregate_repository,
      :record_class,
      :transaction_provider

    attr_accessor :command_handlers,
      :discovered_command_handlers,
      :autodiscover_command_handlers,
      :command_filters

    attr_accessor :event_handlers,
      :discovered_event_handlers,
      :autodiscover_event_handlers

    def self.instance
      @instance ||= new
    end

    def self.reset
      @instance = new
    end

    def initialize
      self.event_store = Sequent::Core::EventStore.new(self)
      self.command_service = Sequent::Core::CommandService.new(self)
      self.record_class = Sequent::Core::EventRecord
      self.transaction_provider = Sequent::Core::Transactions::NoTransactions.new

      self.command_handlers = []
      self.discovered_command_handlers = []
      self.command_filters = []
      self.autodiscover_command_handlers = true

      self.event_handlers = []
      self.discovered_event_handlers = []
      self.autodiscover_event_handlers = true
    end

    def event_store=(event_store)
      @event_store = event_store
      self.aggregate_repository = Sequent::Core::AggregateRepository.new(event_store)
    end

    def all_event_handlers(autodiscover_event_handlers = self.autodiscover_event_handlers)
      return discovered_event_handlers + @event_handlers if autodiscover_event_handlers
      @event_handlers
    end

    def all_command_handlers(autodiscover_command_handlers = self.autodiscover_command_handlers)
      return discovered_command_handlers + @command_handlers if autodiscover_command_handlers
      @command_handlers
    end
  end
end
