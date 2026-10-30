# frozen_string_literal: true

require_relative 'helpers/event_handler_dispatch'
require_relative 'inline_event_publisher'
require_relative 'staged_event_publisher'

module Sequent
  module Core
    #
    # Publishes the events one at a time to all event handlers using an +InlineEventPublisher+,
    # whatever their phase, queueing the events that are published while handling events.
    #
    # @deprecated Use +StagedEventPublisher.with_phases+, or a +StagedEventPublisher+ with an
    #   +InlineEventPublisher+ stage.
    #
    class EventPublisher < StagedEventPublisher
      PublishEventError = Sequent::Core::PublishEventError

      def self.warn_deprecated
        return if @deprecation_warned

        @deprecation_warned = true
        Sequent.logger.warn(
          '[DEPRECATION] Sequent::Core::EventPublisher is deprecated, use ' \
          'Sequent::Core::StagedEventPublisher.with_phases or a Sequent::Core::StagedEventPublisher ' \
          'with a Sequent::Core::InlineEventPublisher stage instead',
        )
      end

      ##
      # @param event_handlers the event handlers to publish to, by default the configured event handlers.
      def initialize(event_handlers = nil)
        EventPublisher.warn_deprecated
        super(immediate: {inline: InlineEventPublisher.new})
        @event_handlers = event_handlers
      end

      def publish_events(events, event_handlers: @event_handlers || configuration.event_handlers)
        super
      end

      # All event handlers handle the events, so their phase does not matter.
      def ensure_valid_phases!(_event_handlers); end

      private

      def stage_event_handlers(_stage_index) = available_event_handlers
    end
  end
end
