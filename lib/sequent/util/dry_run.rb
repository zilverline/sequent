# frozen_string_literal: true

module Sequent
  module Util
    ##
    # Dry run provides the ability to inspect what would
    # happen if the given commands would be executed
    # without actually committing the results.
    # You can inspect which commands are executed
    # and what the resulting events would be
    # with theSequent::Projector's and Sequent::Workflow's
    # that would be invoked (without actually invoking them).
    #
    # Since the Workflow's are not actually invoked new commands
    # resulting from this Workflow will of course not be in the result.
    #
    # Caution: Since the Sequent Configuration is shared between threads this method
    # is not Thread safe.
    #
    # Example usage:
    #
    #   result = Sequent.dry_run(create_foo_command, ping_foo_command)
    #
    #   result.print(STDOUT)
    #
    module DryRun
      EventInvokedHandler = Struct.new(:event, :handler)

      ##
      # Proxies the given EventStore implements commit_events
      # that instead of publish and store just publishes the events.
      class EventStoreProxy
        attr_reader :command_with_events, :event_store

        delegate :load_events_for_aggregates,
                 :load_events,
                 :stream_exists?,
                 :events_exists?,
                 :event_streams_enumerator,
                 :find_event_stream,
                 :position_mark,
                 :load_events_since_marked_position,
                 to: :event_store

        def initialize(result, event_store)
          @event_store = event_store
          @command_with_events = {}
          @result = result
        end

        def commit_events(command, streams_with_events)
          Sequent.configuration.event_publisher.publish_events(streams_with_events.flat_map { |_, events| events })

          new_events = streams_with_events.flat_map { |_, events| events }
          @result.published_command_with_events(command, new_events)
        end

        def update_unique_keys(event_streams)
          # no-op
        end
      end

      ##
      # Records which Projector's and Workflow's are executed
      #
      class RecordingEventPublisher < Sequent::Core::EventPublisher
        attr_reader :projectors, :workflows

        def initialize(result)
          super()
          @result = result
        end

        def process_event(event)
          [*Sequent::Core::Workflow.descendants, *Sequent::Core::Projector.descendants].each do |handler_class|
            next unless handler_class.handles_message?(event)

            if handler_class < Sequent::Workflow
              @result.invoked_workflow(EventInvokedHandler.new(event, handler_class))
            elsif handler_class < Sequent::Projector
              @result.invoked_projector(EventInvokedHandler.new(event, handler_class))
            else
              fail "Unrecognized event_handler #{handler_class} called for event #{event.class}"
            end
          rescue StandardError
            raise PublishEventError.new(handler_class, event)
          end
        end
      end

      ##
      # Contains the result of a dry run.
      #
      # @see #tree
      # @see #print
      #
      class Result
        EventCalledHandlers = Struct.new(:event, :projectors, :workflows)

        def initialize
          @command_with_events = {}
          @event_invoked_projectors = []
          @event_invoked_workflows = []
        end

        def invoked_projector(event_invoked_handler)
          event_invoked_projectors << event_invoked_handler
        end

        def invoked_workflow(event_invoked_handler)
          event_invoked_workflows << event_invoked_handler
        end

        def published_command_with_events(command, events)
          command_with_events[command] = events
        end

        ##
        # Returns the command with events as a tree structure.
        #
        # {
        #   command => [
        #     EventCalledHandlers,
        #     EventCalledHandlers,
        #     EventCalledHandlers,
        #   ]
        # }
        #
        # The EventCalledHandlers contains an Event with the
        # lists of `Sequent::Projector`s and `Sequent::Workflow`s
        # that were called.
        #
        def tree
          command_with_events.reduce({}) do |memo, (command, events)|
            events_to_handlers = events.map do |event|
              for_current_event = ->(pair) { pair.event == event }
              EventCalledHandlers.new(
                event,
                event_invoked_projectors.select(&for_current_event).map(&:handler),
                event_invoked_workflows.select(&for_current_event).map(&:handler),
              )
            end
            memo[command] = events_to_handlers
            memo
          end
        end

        ##
        # Prints the output from #tree to the given `io`
        #
        def print(io)
          tree.each_with_index do |(command, event_called_handlerss), index|
            io.puts '+++++++++++++++++++++++++++++++++++' if index == 0
            io.puts "Command: #{command.class} resulted in #{event_called_handlerss.length} events"
            event_called_handlerss.each_with_index do |event_called_handlers, i|
              io.puts '' if i > 0
              io.puts "-- Event #{event_called_handlers.event.class} was handled by:"
              io.puts "-- Projectors: [#{event_called_handlers.projectors.join(', ')}]"
              io.puts "-- Workflows: [#{event_called_handlers.workflows.join(', ')}]"
            end

            io.puts '+++++++++++++++++++++++++++++++++++'
          end
        end

        private

        attr_reader :command_with_events, :event_invoked_projectors, :event_invoked_workflows
      end

      ##
      # Main method of the DryRun.
      #
      # Caution: Since the Sequent Configuration is changed and is shared between threads this method
      # is not Thread safe.
      #
      # After invocation the sequent configuration is reset to the state it was before
      # invoking this method.
      #
      # @param commands - the commands to dry run
      # @return Result - the Result of the dry run. See Result.
      #
      def self.these_commands(commands)
        current_event_store = Sequent.configuration.event_store
        current_event_publisher = Sequent.configuration.event_publisher
        current_transaction_provider = Sequent.configuration.transaction_provider

        result = Result.new

        Sequent.configuration.event_store = EventStoreProxy.new(result, current_event_store)
        Sequent.configuration.event_publisher = RecordingEventPublisher.new(result)
        Sequent.configuration.transaction_provider =
          Sequent::Core::Transactions::ReadOnlyActiveRecordTransactionProvider.new(current_transaction_provider)

        Sequent.command_service.execute_commands(*commands)

        result
      ensure
        Sequent.configuration.event_store = current_event_store
        Sequent.configuration.event_publisher = current_event_publisher
        Sequent.configuration.transaction_provider = current_transaction_provider
      end
    end
  end
end
