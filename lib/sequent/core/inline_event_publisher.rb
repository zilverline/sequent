# frozen_string_literal: true

require_relative 'helpers/event_handler_dispatch'

module Sequent
  module Core
    #
    # Publishes the events one at a time. For each event the projectors are invoked before the other
    # event handlers (like workflows), so these can use the projections updated by the event they are
    # handling. The batch handlers (see +MessageHandler#on_batch+) receive a batch of a single event.
    #
    # The projectors instantiated for the events are flushed after handling all events.
    #
    class InlineEventPublisher
      include Helpers::EventHandlerDispatch

      private

      def process_events(event_handlers, events)
        projectors, other_handlers = event_handlers.partition do |event_handler|
          Helpers::EventHandlers.handler_class(event_handler) < Projector
        end
        plan = Helpers::DispatchPlan.new(projectors + other_handlers)
        instances = {}
        events.each { |event| process_event(plan, event, instances) }

        instances.each_value do |handler|
          with_publish_event_error(handler, events.last) { handler.flush } if handler.is_a?(Projector)
        end
      end

      # Dispatches the +event+ to the event handlers of the +plan+ that handle it, instantiating the event handler
      # classes in +instances+ when these handle their first event.
      def process_event(plan, event, instances)
        fail ArgumentError, 'event is required' if event.nil?

        Sequent.logger.debug("[InlineEventPublisher] Publishing event #{event.class}") if Sequent.logger.debug?

        plan.entries(event).each do |entry|
          with_publish_event_error(entry.event_handler, event) do
            match = entry.for_event(event)
            next unless match

            handler = event_handler_instance(match.event_handler, instances)
            if match.handler_blocks
              handler.handle_matched_message(event, match.handler_blocks)
            else
              handler.handle_message(event)
            end
          end
        end
      end

      def event_handler_instance(event_handler, instances)
        return event_handler unless event_handler.is_a?(Class)

        instances[event_handler] ||= instantiate_event_handler(event_handler)
      end
    end
  end
end
