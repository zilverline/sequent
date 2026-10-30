# frozen_string_literal: true

module Sequent
  module Core
    module Helpers
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
          # The match of the +event_handler+ for the +event+ using its +message_router+, or nil when it does not handle
          # the event. Without a +message_router+ the event handler gets every event using +handle_message+.
          def self.of(event_handler, message_router, event)
            return new(event_handler, nil) if message_router.nil?

            handler_blocks = message_router.match_message(event)
            new(event_handler, handler_blocks) unless handler_blocks.empty?
          end

          # The match for an +event+ of the class this match was determined for.
          def for_event(_event) = self

          def dispatch(event)
            if handler_blocks
              event_handler.dispatch_message(event, handler_blocks)
            else
              event_handler.handle_message(event)
            end
          end
        end

        # An event handler that is matched for every event, since its matches do not only depend on the class of the
        # event.
        PerEventMatcher = Data.define(:event_handler, :message_router) do
          # The match for the +event+, or nil when the event handler does not handle it.
          def for_event(event) = Match.of(event_handler, message_router, event)
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
          per_event ? entries.filter_map { |entry| entry.for_event(event) } : entries
        end

        private

        # The matches of the event handlers that only match events by their class, and the matchers of the other event
        # handlers, in the order of the event handlers. Also returns whether there are any of the latter.
        def entries_for_event_class(event)
          entries = @event_handlers.filter_map do |event_handler|
            message_router = message_router(event_handler)
            if message_router&.routes&.empty?
              Match.of(event_handler, message_router, event)
            else
              PerEventMatcher.new(event_handler, message_router)
            end
          end
          [entries.freeze, entries.any?(PerEventMatcher)]
        end

        # The message router of the +event_handler+, or nil when it gets the events using +handle_message+.
        def message_router(event_handler)
          handler_class = event_handler.class
          @message_routers.fetch(handler_class) do
            @message_routers[handler_class] = (handler_class.message_router if dispatchable?(handler_class))
          end
        end

        def dispatchable?(handler_class)
          handler_class < MessageHandler &&
            handler_class.instance_method(:handle_message).owner == MessageHandler
        end
      end
    end
  end
end
