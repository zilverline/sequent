# frozen_string_literal: true

require_relative 'aggregate_observer'
require_relative 'helpers/event_serialization'

module Sequent
  module Core
    #
    # Checks that the events that aggregates apply do not change when they are stored, so the aggregates and
    # projectors that get them when they are applied see the same values as when they are loaded or replayed (see
    # +Helpers::EventSerialization+). By default it raises an +EventSerializationError+, for development and specs;
    # given a block it passes the error to the block instead, for instance to report it in production:
    #
    #   config.aggregate_observers << Sequent::Core::EventSerializationObserver.new
    #   config.aggregate_observers << Sequent::Core::EventSerializationObserver.new { |error| report(error) }
    #
    # It is not autoregistered, since it serializes and deserializes every event.
    #
    class EventSerializationObserver < AggregateObserver
      self.skip_autoregister = true

      def initialize(&on_error)
        super()
        @on_error = on_error || ->(error) { fail error }
      end

      on is_a(Event) do |event|
        error = Helpers::EventSerialization.serialization_error(event)
        @on_error.call(error) if error
      end
    end
  end
end
