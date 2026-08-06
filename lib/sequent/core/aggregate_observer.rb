# frozen_string_literal: true

require_relative 'helpers/message_handler'

module Sequent
  module Core
    # Observe events as they are generated and applied by the domain
    # code. The event handler is invoked immediately as the event is
    # applied.
    #
    # Example usage:
    #
    #   class MyObserver < Sequent::Core::AggregateObserver
    #     on BankAccountCredited do |event|
    #       bank_account =
    #         Sequent.aggregate_repository.load_aggregate(event.aggregate_id)
    #       ledger = load_ledger(bank_account)
    #       ledger.record_credit(bank_account, event.amount)
    #     end
    #
    # Compared to workflows an observer is part of the domain and can
    # directly invoke methods which may generate new events. But they
    # cannot use any view projections or external systems.
    #
    # Use (async) workflows if the view schema or external systems
    # need to be accessed and execute commands based on the results.
    class AggregateObserver
      include Helpers::MessageHandler
      extend ActiveSupport::DescendantsTracker

      class << self
        attr_accessor :abstract_class, :skip_autoregister
      end
    end

    #
    # Utility class containing all subclasses of AggregateObserver.
    #
    class AggregateObservers
      class << self
        def aggregate_observers
          AggregateObserver.descendants
        end

        def all
          aggregate_observers
        end
      end
    end
  end
end
