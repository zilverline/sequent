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
        instantiate_event_handlers(event_handlers, events).each do |handler|
          events.each do |event|
            with_publish_event_error(handler, event) { handler.handle_message(event) }
          end
          next unless instantiated_projector?(event_handlers, handler)

          with_publish_event_error(handler, events.last) { handler.flush }
        end
      end
    end
  end
end
