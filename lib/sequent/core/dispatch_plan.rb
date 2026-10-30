# frozen_string_literal: true

module Sequent
  module Core
    #
    # Determines which event handlers handle an event, and with which handler blocks, so every event handler is
    # matched at most once per event. The matches of event handlers that only match events by their class (like all
    # projectors) are determined once per event class. Other event handlers are matched for every event.
    #
    # An event handler that does not use the message router of a +MessageHandler+, or overrides +handle_message+, gets
    # every event using +handle_message+, like before.
    #
    # A dispatch plan is meant for a single batch of events, since it does not notice changes to the handlers of the
    # event handlers.
    #
    class DispatchPlan
      # An event handler that handles an event, with the handler blocks that handle it, or +nil+ when the event is
      # passed to +handle_message+.
      Match = Data.define(:event_handler, :handler_blocks) do
        def dispatch(event)
          if handler_blocks
            event_handler.dispatch_message(event, handler_blocks)
          else
            event_handler.handle_message(event)
          end
        end
      end

      def initialize(event_handlers)
        @event_handlers = event_handlers
        @entries_by_event_class = {}
        @message_routers = {}
      end

      ##
      # The matches of the event handlers that handle the +event+, in the order of the event handlers.
      def matches(event)
        entries, per_event = @entries_by_event_class[event.class] ||= entries_for_event_class(event)
        return entries unless per_event

        entries.filter_map do |entry|
          next entry if entry.is_a?(Match)

          match(entry, event)
        end
      end

      private

      # The matches of the event handlers that only match events by their class, and the event handlers that are
      # matched for every event, in the order of the event handlers. Also returns whether there are any of the latter.
      def entries_for_event_class(event)
        per_event = false
        entries = @event_handlers.filter_map do |event_handler|
          message_router = message_router(event_handler)
          if message_router&.routes&.empty?
            match(event_handler, event)
          else
            per_event = true
            event_handler
          end
        end
        [entries.freeze, per_event]
      end

      def match(event_handler, event)
        message_router = message_router(event_handler)
        return Match.new(event_handler, nil) if message_router.nil?

        handler_blocks = message_router.match_message(event)
        Match.new(event_handler, handler_blocks) unless handler_blocks.empty?
      end

      # The message router of the +event_handler+, or nil when it gets the events using +handle_message+.
      def message_router(event_handler)
        handler_class = event_handler.class
        @message_routers.fetch(handler_class) do
          @message_routers[handler_class] = (handler_class.message_router if dispatchable?(handler_class))
        end
      end

      def dispatchable?(handler_class)
        handler_class < Helpers::MessageHandler &&
          handler_class.instance_method(:handle_message).owner == Helpers::MessageHandler
      end
    end
  end
end
