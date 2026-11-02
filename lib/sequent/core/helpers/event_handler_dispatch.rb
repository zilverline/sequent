# frozen_string_literal: true

module Sequent
  module Core
    class ProjectorMigrationError < RuntimeError; end

    # Raised when an +InlineEventPublisher+ or +BulkEventPublisher+ is asked to publish events while it
    # is publishing events. Use a +StagedEventPublisher+ to queue these events instead.
    class NestedEventPublishingError < RuntimeError; end

    # Raised when an event handler fails to handle an event.
    class PublishEventError < RuntimeError
      attr_reader :event_handler_class, :event

      def initialize(event_handler_class, event)
        super()
        @event_handler_class = event_handler_class
        @event = event
      end

      def message
        "Event Handler: #{@event_handler_class.inspect}\nEvent: #{@event.inspect}\nCause: #{cause.inspect}"
      end
    end

    module Helpers
      #
      # Dispatches events to event handlers. Included by the +InlineEventPublisher+ and the
      # +BulkEventPublisher+, which implement +process_events+ to dispatch the events in their own way.
      #
      # These publishers only publish: an event handler cannot publish events while events are being
      # published. Use them as stages of a +StagedEventPublisher+, which queues these events.
      #
      module EventHandlerDispatch
        ##
        # Publishes the +events+ to the +event_handlers+. An event handler is either an instance, which
        # handles all events, or a class, which is instantiated for every batch of events it handles (see
        # +Helpers::EventHandlers+).
        #
        # @raise NestedEventPublishingError when called while publishing events.
        def publish_events(events, event_handlers: configuration.event_handlers)
          return if configuration.disable_event_handlers

          if Thread.current[publishing_key]
            fail NestedEventPublishingError,
                 "#{self.class} cannot publish events while publishing events, use a StagedEventPublisher instead"
          end

          begin
            Thread.current[publishing_key] = true
            handle_events(events, event_handlers)
          ensure
            Thread.current[publishing_key] = nil
          end
        end

        ##
        # Handles the +events+ using the +event_handlers+. Used by the +StagedEventPublisher+ to let a
        # stage handle a batch of events.
        def handle_events(events, event_handlers)
          process_events(event_handlers, events)
        end

        ##
        # Called by the +CommandService+ around processing commands. Nothing is deferred.
        def defer_events
          yield
        end

        ##
        # Called by the +CommandService+ when no more commands are queued. Nothing is deferred.
        def handle_deferred_events
          false
        end

        private

        def publishing_key
          @publishing_key ||= :"#{self.class.name}_#{object_id}_publishing"
        end

        def instantiate_event_handler(handler_class)
          handler_class.new
        end

        # Raises a PublishEventError for the +event+ when the block fails, unless it failed with a
        # ProjectorMigrationError or a PublishEventError.
        def with_publish_event_error(handler, event)
          yield
        rescue StandardError => e
          publish_event_error_handler(handler).call([event], e)
        end

        # Raises a PublishEventError for the first of the +events+ that the +handler+ failed to handle,
        # unless it failed with a ProjectorMigrationError.
        def publish_event_error_handler(handler)
          ->(events, error) do
            fail error if error.is_a?(ProjectorMigrationError) || error.is_a?(PublishEventError)

            fail PublishEventError.new(EventHandlers.handler_class(handler), events.first)
          end
        end

        def configuration
          Sequent.configuration
        end
      end
    end
  end
end
