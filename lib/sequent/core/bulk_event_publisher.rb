# frozen_string_literal: true

require_relative 'helpers/event_handler_dispatch'

module Sequent
  module Core
    #
    # Publishes all events to each event handler in turn, so an event handler handles all events before
    # the next event handler starts. A projector instantiated for the events is flushed after it handled
    # the events.
    #
    class BulkEventPublisher
      include Helpers::EventHandlerDispatch

      private

      def process_events(event_handlers, events)
        plan = Helpers::DispatchPlan.new(event_handlers)
        event_handlers.each do |event_handler|
          next unless with_publish_event_error(event_handler, events.first) { plan.handles_any?(event_handler, events) }

          handler = event_handler.is_a?(Class) ? instantiate_event_handler(event_handler) : event_handler
          events.each do |event|
            with_publish_event_error(handler, event) do
              dispatch(handler, event, plan.handler_blocks(event, event_handler))
            end
          end
          next unless event_handler.is_a?(Class) && handler.is_a?(Projector)

          with_publish_event_error(handler, events.last) { handler.flush }
        end
      end

      # Dispatches the +event+ to the matched +handler_blocks+ of the +handler+, or using +handle_message+ when
      # the handler is not a message handler.
      def dispatch(handler, event, handler_blocks)
        if handler_blocks.nil?
          handler.handle_message(event)
        elsif !handler_blocks.empty?
          handler.dispatch_message(event, handler_blocks)
        end
      end
    end
  end
end
