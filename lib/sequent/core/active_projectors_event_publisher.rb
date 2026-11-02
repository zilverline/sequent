# frozen_string_literal: true

require_relative 'helpers/event_handler_dispatch'
require_relative 'inline_event_publisher'
require_relative 'staged_event_publisher'

module Sequent
  module Core
    class UnknownActiveProjectorError < ProjectorMigrationError; end
    class DifferentProjectorVersionIsActiveError < ProjectorMigrationError; end
    class ProjectorIsActivatingError < ProjectorMigrationError; end

    #
    # Wraps an event publisher, which only publishes the events to the Projectors that are marked
    # active in the projector_states table (and to all other event handlers). Also fails if there are
    # unknown active projectors. This allows upgrading to new code (with new projectors) without
    # having to shutdown the old code first, as the old code will start failing as soon as the new
    # code's Sequent configuration is activated (using `Sequent#activate_current_configuration!`).
    #
    #   Sequent.configure do |config|
    #     config.event_publisher = Sequent::Core::ActiveProjectorsEventPublisher.new(
    #       Sequent::Core::StagedEventPublisher.with_phases,
    #     )
    #   end
    #
    class ActiveProjectorsEventPublisher
      attr_reader :event_publisher

      ##
      # @param event_publisher the event publisher to publish the events to, with the event handlers
      #   that are not inactive projectors.
      def initialize(event_publisher = StagedEventPublisher.new(immediate: {inline: InlineEventPublisher.new}))
        @event_publisher = event_publisher
      end

      def publish_events(events, event_handlers: Sequent.configuration.event_handlers)
        return if Sequent.configuration.disable_event_handlers

        # Publish all events inside a transaction to ensure consistency with the projector state
        # (active or not) and updating the projector tables. Normally a transaction is already
        # active due to using the `CommandService#execute_command`, but if this event publisher is
        # used directly it is also important to run inside a transaction.
        Sequent.configuration.transaction_provider.transaction do
          ensure_no_unknown_active_projectors!(event_handlers)
          active_event_handlers = event_handlers.select { |x| active?(Helpers::EventHandlers.handler_class(x)) }
          event_publisher.publish_events(events, event_handlers: active_event_handlers)
        end
      end

      def defer_events(&)
        event_publisher.defer_events(&)
      end

      def ensure_valid_phases!(event_handlers)
        event_publisher.ensure_valid_phases!(event_handlers) if event_publisher.respond_to?(:ensure_valid_phases!)
      end

      def handle_deferred_events
        event_publisher.handle_deferred_events
      end

      private

      def ensure_no_unknown_active_projectors!(event_handlers)
        registered_projectors = event_handlers.filter_map do |event_handler|
          handler_class = Helpers::EventHandlers.handler_class(event_handler)
          handler_class.name if handler_class <= Projector
        end
        activated_projectors = Projectors.projector_states
          .values
          .select { |s| s.active_version.present? || s.activating_version.present? }
          .to_set(&:name)
        unknown_active_projectors = activated_projectors - registered_projectors
        if unknown_active_projectors.present?
          fail UnknownActiveProjectorError,
               "cannot publish event when unknown projectors are active #{unknown_active_projectors}"
        end
      end

      def active?(handler_class)
        return true unless handler_class <= Projector

        version = handler_class.version
        return true if version.nil?

        projector_state = Projectors.projector_states[handler_class.name]
        return false if projector_state.nil?

        if projector_state.activating_version.present?
          # Activating projectors are replaying the last remaining events before going live, so new events cannot be
          # processed until activation is completed.
          fail ProjectorIsActivatingError, "projector #{handler_class} is currently activating"
        end

        # Projector is not yet active (probably just replaying)
        return false if projector_state.active_version.nil?

        # Projector is active and has the same version
        return true if projector_state.active_version == version

        # A different projector version is active, so we cannot write new events since our projector version is not
        # compatible with the active version.
        fail DifferentProjectorVersionIsActiveError,
             "projector #{handler_class} version #{version} does not match state #{projector_state}"
      end
    end
  end
end
