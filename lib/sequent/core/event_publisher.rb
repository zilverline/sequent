# frozen_string_literal: true

require_relative 'helpers/dispatch_plan'

module Sequent
  module Core
    class ProjectorMigrationError < RuntimeError; end

    #
    # EventPublisher ensures that, for every thread, events will be published
    #   in the order in which they are queued for publishing.
    #
    # This potentially introduces a wrinkle into your plans:
    #   You therefore should not split a "unit of work" across multiple threads.
    #
    # If you want other behaviour, you are free to implement your own version of EventPublisher
    #   and configure Sequent to use it.
    #
    class EventPublisher
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

      def publish_events(events)
        return if configuration.disable_event_handlers

        events_queue.concat(events)
        process_events_if_not_already_processing
      end

      private

      def events_queue
        Thread.current[:events_queue] ||= []
      end
      def events_queue=(queue)
        Thread.current[:events_queue] = queue
      end

      def process_events_if_not_already_processing
        Sequent::Util.skip_if_already_processing(:events_queue_lock) do
          until events_queue.empty?
            events = events_queue
            self.events_queue = []
            process_events(configuration.event_handlers, events)
          end
        ensure
          self.events_queue = []
        end
      end

      # Handles the +events+ using the registered +event_handlers+. An event handler class (with the +batch+
      # lifetime) gets a new instance for the events when it handles the first of them. The projectors instantiated
      # for the events are flushed after handling the events, and before another event handler handles an event, so
      # other event handlers see their changes.
      def process_events(event_handlers, events)
        plan = Helpers::DispatchPlan.new(event_handlers)
        batch_handlers = {}
        events.each { |event| process_event(event_handlers, event, plan:, batch_handlers:) }
        flush_projectors(batch_handlers, events.last)
      end

      # Dispatches the +event+ to the +event_handlers+ that handle it, using the +plan+ of the batch of events and the
      # +batch_handlers+ instantiated for the batch so far.
      def process_event(event_handlers, event, plan: Helpers::DispatchPlan.new(event_handlers), batch_handlers: {})
        fail ArgumentError, 'event is required' if event.nil?

        Sequent.logger.debug("[EventPublisher] Publishing event #{event.class}") if Sequent.logger.debug?

        plan.matches(event).each do |match|
          event_handler = match.event_handler
          if event_handler.is_a?(Class)
            dispatch(match, event, batch_handlers[event_handler] ||= event_handler.new)
          else
            flush_projectors(batch_handlers, event) unless batch_handlers.empty?
            dispatch(match, event, event_handler)
          end
        end
      end

      def dispatch(match, event, event_handler)
        match.dispatch(event, event_handler)
      rescue ProjectorMigrationError
        raise
      rescue StandardError
        raise PublishEventError.new(event_handler.class, event)
      end

      # Flushes the changes of the instantiated projectors of the batch, which were made while handling the events
      # up to the +event+.
      def flush_projectors(batch_handlers, event)
        batch_handlers.each_value do |event_handler|
          next unless event_handler.is_a?(Projector) && event_handler.pending_changes?

          event_handler.flush
        rescue ProjectorMigrationError
          raise
        rescue StandardError
          raise PublishEventError.new(event_handler.class, event)
        end
      end

      def configuration
        Sequent.configuration
      end
    end
  end
end
