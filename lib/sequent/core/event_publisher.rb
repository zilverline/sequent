# frozen_string_literal: true

module Sequent
  module Core
    class ProjectorMigrationError < RuntimeError; end
    class UnknownActiveProjectorError < ProjectorMigrationError; end
    class ReplayingProjectorMismatchError < ProjectorMigrationError; end
    class NewerProjectorIsActiveError < ProjectorMigrationError; end

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

        ensure_no_unknown_active_projectors!

        events.each { |event| events_queue.push(event) }
        process_events
      end

      def replay_events(events)
        ensure_only_replaying_projectors_subscribed!

        events.each { |event| events_queue.push(event) }
        process_events
      end

      private

      def events_queue
        Thread.current[:events_queue] ||= Queue.new
      end

      def process_events
        Sequent::Util.skip_if_already_processing(:events_queue_lock) do
          process_event(events_queue.pop) until events_queue.empty?
        ensure
          events_queue.clear
        end
      end

      def process_event(event)
        fail ArgumentError, 'event is required' if event.nil?

        Sequent.logger.debug("[EventPublisher] Publishing event #{event.class}") if Sequent.logger.debug?

        configuration.event_handlers.each do |handler|
          handler.handle_message event
        rescue ProjectorMigrationError
          raise
        rescue StandardError
          raise PublishEventError.new(handler.class, event)
        end
      end

      def configuration
        Sequent.configuration
      end

      def ensure_no_unknown_active_projectors!
        expected_version = Sequent.migrations_class&.version
        return if expected_version.nil?

        registered_projectors = Migratable.projectors.to_set(&:name)
        active_projectors = Projectors
          .projector_states
          .values
          .select { |s| s.active_version == expected_version }
          .to_set(&:name)
        unknown_active_projectors = active_projectors - registered_projectors
        if unknown_active_projectors.present?
          fail UnknownActiveProjectorError,
               "cannot publish event when unknown projectors are active #{unknown_active_projectors}"
        end
      end

      def ensure_only_replaying_projectors_subscribed!
        return unless Sequent.migrations_class

        registered_projectors = Migratable.projectors.to_set(&:name)
        projector_states = Projectors.projector_states
        replaying_projectors = projector_states
          .values
          .select { |state| state.replaying? || state.activating? }
          .to_set(&:name)
        if registered_projectors != replaying_projectors
          fail ReplayingProjectorMismatchError,
               "cannot replay event when different projectors are replaying #{replaying_projectors}"
        end
      end
    end
  end
end
