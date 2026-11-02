# frozen_string_literal: true

require_relative 'helpers/event_handler_dispatch'

module Sequent
  module Core
    #
    # Publishes all events at once to each event handler (see +MessageHandler#handle_messages+). A
    # projector instantiated for the events is flushed after it handled the events.
    #
    class BulkEventPublisher
      include Helpers::EventHandlerDispatch

      private

      def process_events(event_handlers, events)
        plan = Helpers::DispatchPlan.new(event_handlers)
        event_handlers.each do |event_handler|
          with_publish_event_error(event_handler, events.first) do
            next unless plan.handles_any?(event_handler, events)

            handler = event_handler.is_a?(Class) ? instantiate_event_handler(event_handler) : event_handler
            handler.handle_messages(events, on_error: publish_event_error_handler(handler)) do |event|
              plan.handler_blocks(event, event_handler)
            end
            next unless event_handler.is_a?(Class) && handler.is_a?(Projector)

            with_publish_event_error(handler, events.last) { handler.flush }
          end
        end
      end
    end
  end
end
