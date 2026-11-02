# frozen_string_literal: true

module Sequent
  module Core
    module Helpers
      #
      # Determines which event handlers handle an event, and with which handler blocks, so every event handler is
      # matched at most once per event. The matches of event handlers that only match events by their class (like all
      # projectors) are determined once per event class. Other event handlers are matched for every event, when their
      # turn comes, so their matchers see the changes of the event handlers before them.
      #
      # The event handlers are registered event handlers: instances, or classes (with the +batch+ lifetime) that the
      # event publisher instantiates. An event handler that is not a message handler gets every event using
      # +handle_message+.
      #
      # A dispatch plan is meant for a single batch of events, since it does not notice changes to the handlers of the
      # event handlers.
      #
      class DispatchPlan
        NO_HANDLER_BLOCKS = Set.new.freeze

        # An event handler that handles an event, with the handler blocks that handle it, or +nil+ when the event is
        # passed to +handle_message+.
        Match = Data.define(:event_handler, :handler_blocks) do
          # The match of the +event_handler+ for the +event+ using its +message_router+, or nil when it does not
          # handle the event. Without a +message_router+ the event handler gets every event using +handle_message+.
          def self.of(event_handler, message_router, event)
            return new(event_handler, nil) if message_router.nil?

            handler_blocks = message_router.match_message(event)
            new(event_handler, handler_blocks) unless handler_blocks.empty?
          end

          # The match for an +event+ of the class this match was determined for.
          def for_event(_event) = self
        end

        # An event handler that is matched for every event, since its matches do not only depend on the class of
        # the event.
        PerEventMatcher = Data.define(:event_handler, :message_router) do
          # The match for the +event+, or nil when the event handler does not handle it.
          def for_event(event) = Match.of(event_handler, message_router, event)
        end

        # The entries of the event handlers for an event class, in the order of the event handlers, and by event
        # handler.
        Entries = Data.define(:entries, :by_event_handler)

        def initialize(event_handlers)
          @event_handlers = event_handlers
          @entries_by_event_class = {}
        end

        ##
        # The entries of the event handlers that may handle the +event+, in the order of the event handlers. An entry
        # returns the match for the event using +for_event+, or nil when its event handler does not handle it. Call
        # +for_event+ when the event handler is about to handle the event, so its matchers see the changes of the
        # event handlers before it.
        def entries(event)
          entries_for(event).entries
        end

        ##
        # The handler blocks of the +event_handler+ that handle the +event+, or nil when the event is passed to
        # +handle_message+.
        def handler_blocks(event, event_handler)
          entry = entries_for(event).by_event_handler[event_handler]
          return NO_HANDLER_BLOCKS unless entry

          match = entry.for_event(event)
          match ? match.handler_blocks : NO_HANDLER_BLOCKS
        end

        ##
        # Whether the +event_handler+ handles any of the +events+.
        def handles_any?(event_handler, events)
          events.any? do |event|
            entry = entries_for(event).by_event_handler[event_handler]
            entry&.for_event(event)
          end
        end

        private

        def entries_for(event)
          @entries_by_event_class[event.class] ||= entries_for_event_class(event)
        end

        # The matches of the event handlers that only match events by their class, and the matchers of the other
        # event handlers.
        def entries_for_event_class(event)
          entries = @event_handlers.filter_map do |event_handler|
            message_router = message_router(event_handler)
            if message_router&.routes&.empty?
              Match.of(event_handler, message_router, event)
            else
              PerEventMatcher.new(event_handler, message_router)
            end
          end
          Entries.new(entries.freeze, entries.to_h { |entry| [entry.event_handler, entry] }.compare_by_identity.freeze)
        end

        # The message router of the +event_handler+, or nil when it is not a message handler.
        def message_router(event_handler)
          handler_class = EventHandlers.handler_class(event_handler)
          handler_class.message_router if handler_class < MessageHandler
        end
      end
    end
  end
end
