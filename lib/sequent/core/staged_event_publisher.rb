# frozen_string_literal: true

require_relative 'inline_event_publisher'
require_relative 'bulk_event_publisher'

module Sequent
  module Core
    #
    # Publishes events to stages, one stage at a time. Every stage handles the events for the event
    # handlers with its phase (see +Projector.phase+ and +Workflow.phase+), and is an
    # +InlineEventPublisher+, a +BulkEventPublisher+ or any other object that includes
    # +Helpers::EventHandlerDispatch+, so every stage has its own dispatching strategy.
    #
    # Events that are published while handling events (for example by an event handler) are queued
    # and handled afterwards, with the event handlers that were available when publishing the
    # events that are being handled.
    #
    # A stage is only started after all earlier stages have fully handled every event published so
    # far, and handling always continues with the earliest stage that has pending events. So the
    # events published to a later stage are always fully handled by all earlier stages first.
    #
    # When the events are published by the +CommandService+, only the +immediate+ stages handle the
    # events of each command right away. The +deferred+ stages wait until no commands are queued
    # anymore, so these stages handle the events of all commands executed so far at once. Commands
    # executed by the event handlers of a deferred stage (for example by a workflow) are processed
    # before the next stage is started, and their events are handled by the earlier stages first. When
    # events are published outside the +CommandService+ (for example directly) all stages handle the
    # events right away.
    #
    # A stage without event handlers is skipped.
    #
    # The default configuration uses the stages created by +with_phases+. You can configure any other
    # stages, with any phase names, as long as every event handler declares one of these phases:
    #
    #   Sequent.configure do |config|
    #     config.event_publisher = Sequent::Core::StagedEventPublisher.new(
    #       # First update the projections after every command, so the command handlers of the next
    #       # commands can use them...
    #       immediate: {inline: Sequent::Core::InlineEventPublisher.new},
    #       # ...and let the workflows with the `reporting` phase handle the events of all commands at
    #       # once.
    #       deferred: {reporting: Sequent::Core::BulkEventPublisher.new},
    #     )
    #   end
    #
    class StagedEventPublisher
      attr_reader :stages, :phases

      ##
      # Creates a StagedEventPublisher with a stage per phase:
      #
      # - +bulk+: the projectors with the +bulk+ phase, which handle all events of each command at
      #   once.
      # - +inline+: the projectors and workflows with the +inline+ phase (the default), which handle
      #   the events of each command right away, one event at a time.
      # - +before_commit+: the workflows with the +before_commit+ phase, which handle the events of
      #   all commands at once when no more commands are queued.
      #
      # To only publish events to the active projectors, wrap it in an
      # +ActiveProjectorsEventPublisher+.
      def self.with_phases
        new(
          immediate: {bulk: BulkEventPublisher.new, inline: InlineEventPublisher.new},
          deferred: {before_commit: BulkEventPublisher.new},
        )
      end

      ##
      # Creates a new StagedEventPublisher.
      #
      # @param immediate the stages that handle the events of each command right away, by phase, in
      #   order. Each stage fully handles all published events before the next stage is started.
      # @param deferred the stages that handle the events of all commands at once when no more
      #   commands are queued, by phase, in order. These stages run after the immediate stages.
      def initialize(immediate:, deferred: {})
        fail ArgumentError, 'at least one immediate stage is required' if immediate.blank?

        duplicate_phases = immediate.keys & deferred.keys
        fail ArgumentError, "duplicate phases #{duplicate_phases}" if duplicate_phases.present?

        @stages = immediate.merge(deferred).freeze
        @phases = @stages.keys
        @dispatchers = @stages.values
        @immediate_stages = immediate.size
        key = "#{self.class.name}_#{object_id}"
        @events_queue_key = :"#{key}_events_queue"
        @event_handlers_key = :"#{key}_event_handlers"
        @processing_key = :"#{key}_processing"
        @pending_key = :"#{key}_pending"
        @deferring_key = :"#{key}_deferring"
      end

      ##
      # Fails when an event handler declares a phase without a stage, since it would not handle any
      # events.
      def ensure_valid_phases!(event_handlers)
        event_handlers.each do |event_handler|
          phase = Helpers::EventHandlers.phase(event_handler)
          next if @phases.include?(phase)

          fail ArgumentError,
               "phase #{phase.inspect} of #{Helpers::EventHandlers.handler_class(event_handler)} " \
               "is not one of the phases #{@phases}"
        end
      end

      ##
      # Publishes the +events+ to the stages, which handle the events for the given +event_handlers+
      # with their phase. Events published while handling events are queued.
      def publish_events(events, event_handlers: configuration.event_handlers)
        return if configuration.disable_event_handlers

        ensure_valid_phases!(event_handlers)
        events_queue.concat(events)
        self.available_event_handlers = event_handlers
        process_events_if_not_already_processing
      end

      ##
      # Defers the deferred stages until +handle_deferred_events+ is called.
      # The events that are still pending when the block completes (or fails) are discarded.
      def defer_events
        deferring = deferring?
        Thread.current[@deferring_key] = true
        yield
      ensure
        Thread.current[@deferring_key] = deferring
        clear_pending unless deferring
      end

      ##
      # Lets the earliest deferred stage with pending events handle these events. The events
      # published while handling these events are only handled by the immediate stages, the later
      # stages remain deferred.
      #
      # @return +true+ if a deferred stage handled events, +false+ if there were no pending events.
      def handle_deferred_events
        handled = false
        Sequent::Util.skip_if_already_processing(@processing_key) do
          add_pending(take_queued_events)
          handled = handle_pending(handle_deferred_stage: true)
        ensure
          self.events_queue = []
        end
        handled
      end

      private

      def process_events_if_not_already_processing
        Sequent::Util.skip_if_already_processing(@processing_key) do
          until events_queue.empty?
            add_pending(take_queued_events)
            handle_pending(handle_deferred_stage: false)
          end
        ensure
          self.events_queue = []
          # Unless deferred, all stages have handled the events (or failed to do so).
          clear_pending unless deferring?
        end
      end

      # Lets the earliest stage with pending events handle these events, until no stage has pending
      # events, or the earliest stage with pending events is deferred. When +handle_deferred_stage+ is
      # +true+, the first deferred stage with pending events handles its events as well.
      #
      # @return whether a deferred stage handled events.
      def handle_pending(handle_deferred_stage:)
        handled_deferred_stage = false

        while (stage_index = pending.index(&:present?))
          if stage_index >= @immediate_stages && deferring?
            break if handled_deferred_stage || !handle_deferred_stage

            handled_deferred_stage = true
          end

          stage_events = pending[stage_index]
          pending[stage_index] = []

          @dispatchers[stage_index].handle_events(stage_events, stage_event_handlers(stage_index))

          # Any events published by this stage's event handlers need to be handled by all stages.
          add_pending(take_queued_events)
        end

        handled_deferred_stage
      end

      def events_queue
        Thread.current[@events_queue_key] ||= []
      end

      def events_queue=(queue)
        Thread.current[@events_queue_key] = queue
      end

      def take_queued_events
        events = events_queue
        self.events_queue = []
        events
      end

      # The event handlers available when the events being handled were published.
      def available_event_handlers = Thread.current[@event_handlers_key] || []

      def available_event_handlers=(event_handlers)
        Thread.current[@event_handlers_key] = event_handlers
      end

      def deferring? = Thread.current[@deferring_key] == true

      # The available event handlers with the phase of the stage.
      def stage_event_handlers(stage_index)
        available_event_handlers.select { |event_handler| Helpers::EventHandlers.phase(event_handler) == @phases[stage_index] }
      end

      # Each stage has its own queue of events that it still needs to handle.
      def pending
        Thread.current[@pending_key] ||= @dispatchers.map { [] }
      end

      # Events are not kept for stages without event handlers, so the events of a large transaction
      # are not kept in memory for nothing.
      def add_pending(events)
        return if events.blank?

        pending.each_with_index do |queue, stage_index|
          queue.concat(events) if stage_event_handlers(stage_index).present?
        end
      end

      def clear_pending
        Thread.current[@pending_key] = nil
        Thread.current[@event_handlers_key] = nil
      end

      def configuration
        Sequent.configuration
      end
    end
  end
end
