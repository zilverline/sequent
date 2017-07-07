require 'thread_safe'

module Sequent
  module Test
    ##
    # Use in tests
    #
    # This provides a nice DSL for event based testing of your CommandHandler like
    #
    # given_events InvoiceCreatedEvent.new(args)
    # when_command PayInvoiceCommand(args)
    # then_events InvoicePaidEvent(args)
    #
    # Example for Rspec config
    #
    # RSpec.configure do |config|
    #   config.include Sequent::Test::CommandHandlerHelpers
    # end
    #
    # Then in a spec
    #
    # describe InvoiceCommandHandler do
    #
    #   before :each do
    #     @event_store = Sequent::Test::CommandHandlerHelpers::FakeEventStore.new
    #     @repository = Sequent::Core::AggregateRepository.new(@event_store)
    #     @command_handler = InvoiceCommandHandler.new(@repository)
    #   end
    #
    #   it "marks an invoice as paid" do
    #     given_events InvoiceCreatedEvent.new(args)
    #     when_command PayInvoiceCommand(args)
    #     then_events InvoicePaidEvent(args)
    #   end
    #
    # end
    #
    # The FakeEventStore has a +strict_mode+ option which enforces the same
    # unique constraint as the real database.
    # To enable strict_mode:
    #
    #   FakeEventStore.new(strict_mode: true)
    #
    #
    module CommandHandlerHelpers
      class FakeCommand < Sequent::Core::BaseCommand; end
      class FakeEventStore

        DEFAULT_STRICT_MODE = false

        #
        # Initializes new FakeEventStore
        #
        # +options+
        #   * strict_mode - Default false. Enforces same constraints as the real event store. This means:
        #                     - Sequence numbers per aggregate have to be unique
        #                     - +EventStream+s have to be unique, so there can be only one aggregate_type per aggregate_id
        def initialize(options = {})
          @event_streams = {}
          @all_events = {}
          @stored_events = []
          @strict_mode = options[:strict_mode] || DEFAULT_STRICT_MODE
        end

        def load_events(aggregate_id)
          load_events_for_aggregates([aggregate_id])[0]
        end

        def load_events_for_aggregates(aggregate_ids)
          return [] if aggregate_ids.none?

          aggregate_ids.map do |aggregate_id|
            @event_streams[aggregate_id]
          end.compact.map do |event_stream|
            [event_stream, deserialize_events(@all_events[event_stream.aggregate_id])]
          end
        end

        def find_event_stream(aggregate_id)
          @event_streams[aggregate_id]
        end

        def stored_events
          deserialize_events(@stored_events)
        end

        def commit_events(command, streams_with_events)
          fail ArgumentError.new("command is mandatory") unless command
          ensure_unique!(streams_with_events) if @strict_mode

          streams_with_events.each do |event_stream, events|
            serialized = serialize_events(events)
            @event_streams[event_stream.aggregate_id] = event_stream
            @all_events[event_stream.aggregate_id] ||= []
            @all_events[event_stream.aggregate_id] += serialized
            @stored_events += serialized
          end
        end

        def given_events(events)
          commit_events(FakeCommand.new, to_event_streams(events))
          @stored_events = []
        end

        def stream_exists?(aggregate_id)
          @event_streams.has_key?(aggregate_id)
        end

        private

        def ensure_unique!(streams_with_events)
          ensure_no_duplicate_event_streams!(streams_with_events)

          streams_with_events.each do |event_stream, events|
            ensure_unique_event_stream!(event_stream)

            ensure_no_duplicate_events!(events)

            ensure_unique_events!(event_stream, events)
          end
        end

        # Ensure that given events do not exist in existing events
        def ensure_unique_events!(event_stream, events)
          duplicate_events = deserialize_events(@all_events[event_stream.aggregate_id] || []).select { |stored_event| events.any? { |event| event.aggregate_id == stored_event.aggregate_id && event.sequence_number == stored_event.sequence_number } }
          raise ActiveRecord::RecordNotUnique.new("Non unique aggregate_id / sequence_number: #{duplicate_events.first.aggregate_id} / #{duplicate_events.first.sequence_number}") if duplicate_events.any?
        end

        # Ensure no duplicates exists in given events
        def ensure_no_duplicate_events!(events)
          non_unique_events = events.group_by(&:sequence_number).select { |_, v| v.length > 1 }
          raise ActiveRecord::RecordNotUnique.new("Non unique aggregate_id / sequence_number: #{non_unique_events.first.last.first.aggregate_id} / #{non_unique_events.first.first}") if non_unique_events.any?
        end

        # Ensure that given event_stream does not exist yet
        def ensure_unique_event_stream!(event_stream)
          raise ActiveRecord::RecordNotUnique.new("Non unique aggregate_id: #{event_stream.aggregate_id}") if @event_streams.has_key?(event_stream.aggregate_id) && @event_streams[event_stream.aggregate_id].aggregate_type.to_s != event_stream.aggregate_type.to_s
        end

        # Ensure no duplicates exists in given event_streams
        def ensure_no_duplicate_event_streams!(streams_with_events)
          non_unique_streams = streams_with_events.map { |event_stream, _| event_stream }.group_by(&:aggregate_id).select { |_, v| v.length > 1 }
          raise ActiveRecord::RecordNotUnique.new("Non unique aggregate_id: #{non_unique_streams.first.last.first.aggregate_id}") if non_unique_streams.any?
        end

        def to_event_streams(events)
          # Specs use a simple list of given events. We need a mapping from StreamRecord to the associated events for the event store.
          streams_by_aggregate_id = {}
          events.map do |event|
            event_stream = streams_by_aggregate_id.fetch(event.aggregate_id) do |aggregate_id|
              streams_by_aggregate_id[aggregate_id] =
                find_event_stream(aggregate_id) ||
                begin
                  aggregate_type = FakeEventStore.aggregate_type_for_event(event)
                  raise "cannot find aggregate type associated with creation event #{event}, did you include an event handler in your aggregate for this event?" unless aggregate_type
                  Sequent::Core::EventStream.new(aggregate_type: aggregate_type.name, aggregate_id: aggregate_id)
                end
            end
            [event_stream, [event]]
          end
        end

        def self.aggregate_type_for_event(event)
          @event_to_aggregate_type ||= ThreadSafe::Cache.new
          @event_to_aggregate_type.fetch_or_store(event.class) do |klass|
            Sequent::Core::AggregateRoot.descendants.find { |x| x.message_mapping.has_key?(klass) }
          end
        end

        def serialize_events(events)
          events.map { |event| [event.class.name, Sequent::Core::Oj.dump(event)] }
        end

        def deserialize_events(events)
          events.map do |type, json|
            Class.const_get(type).deserialize_from_json(Sequent::Core::Oj.strict_load(json))
          end
        end
      end

      def given_events *events
        @event_store.given_events(events.flatten(1))
      end

      def when_command command
        raise "@command_handler is mandatory when using the #{self.class}" unless @command_handler
        raise "Command handler #{@command_handler} cannot handle command #{command}, please configure the command type (forgot an include in the command class?)" unless @command_handler.class.handles_message?(command)
        @command_handler.handle_message(command)
        @repository.commit(command)
        @repository.clear
      end

      def then_events(*expected_events)
        expected_classes = expected_events.flatten(1).map { |event| event.class == Class ? event : event.class }
        expect(@event_store.stored_events.map(&:class)).to eq(expected_classes)

        @event_store.stored_events.zip(expected_events.flatten(1)).each_with_index do |(actual, expected), index|
          next if expected.class == Class
          _actual = Sequent::Core::Oj.strict_load(Sequent::Core::Oj.dump(actual.payload))
          _expected = Sequent::Core::Oj.strict_load(Sequent::Core::Oj.dump(expected.payload))
          expect(_actual).to eq(_expected), "#{index+1}th Event of type #{actual.class} not equal\nexpected: #{_expected.inspect}\n     got: #{_actual.inspect}" if expected
        end
      end

      def then_no_events
        then_events
      end

    end
  end
end
