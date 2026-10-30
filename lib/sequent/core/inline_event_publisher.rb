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
        projectors, other_handlers = instantiate_event_handlers(event_handlers, events)
          .partition { |handler| handler.is_a?(Projector) }
        ordered_handlers = projectors + other_handlers
        events.each { |event| process_event(ordered_handlers, event) }

        projectors.each do |projector|
          next unless instantiated_projector?(event_handlers, projector)

          with_publish_event_error(projector, events.last) { projector.flush }
        end
      end

      def process_event(event_handlers, event)
        fail ArgumentError, 'event is required' if event.nil?

        Sequent.logger.debug("[InlineEventPublisher] Publishing event #{event.class}") if Sequent.logger.debug?

        event_handlers.each do |handler|
          with_publish_event_error(handler, event) { handler.handle_message(event) }
        end
      end
    end
  end
end
