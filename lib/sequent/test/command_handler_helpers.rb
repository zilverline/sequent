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
    module CommandHandlerHelpers

      class FakeEventStore
        def initialize
          @event_streams = {}
          @all_events = {}
          @stored_events = []
        end

        def load_events(aggregate_id)
          event_stream = @event_streams[aggregate_id]
          return nil unless event_stream
          [event_stream, deserialize_events(@all_events[aggregate_id])]
        end

        def find_event_stream(aggregate_id)
          @event_streams[aggregate_id]
        end

        def stored_events
          deserialize_events(@stored_events)
        end

        def commit_events(_, streams_with_events)
          streams_with_events.each do |event_stream, events|
            serialized = serialize_events(events)
            @event_streams[event_stream.aggregate_id] = event_stream
            @all_events[event_stream.aggregate_id] ||= []
            @all_events[event_stream.aggregate_id] += serialized
            @stored_events += serialized
          end
        end

        def given_events(events)
          commit_events(nil, to_event_streams(events))
          @stored_events = []
        end

        def stream_exists?(aggregate_id)
          @event_streams.has_key?(aggregate_id)
        end

        private

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
        raise "Command handler #{@command_handler} cannot handle command #{command}, please configure the command type (forgot an include in the command class?)" unless @command_handler.handles_message?(command)
        @command_handler.handle_message(command)
        @repository.commit(command)
        @repository.clear
      end

      def then_events(*expected_events)
        expected_classes = expected_events.flatten(1).map { |event| event.class == Class ? event : event.class }
        expect(@event_store.stored_events.map(&:class)).to eq(expected_classes)

        @event_store.stored_events.zip(expected_events.flatten(1)).each do |actual, expected|
          next if expected.class == Class
          expect(Sequent::Core::Oj.strict_load(Sequent::Core::Oj.dump(actual.payload))).to eq(Sequent::Core::Oj.strict_load(Sequent::Core::Oj.dump(expected.payload))) if expected
        end
      end

      def then_no_events
        then_events
      end

    end
  end
end
