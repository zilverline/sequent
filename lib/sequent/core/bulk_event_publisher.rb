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
        instantiate_event_handlers(event_handlers, events).each do |handler|
          handler.handle_messages(events, on_error: publish_event_error_handler(handler))
          next unless instantiated_projector?(event_handlers, handler)

          with_publish_event_error(handler, events.last) { handler.flush }
        end
      end
    end
  end
end
