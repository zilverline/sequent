require 'thread_safe'
require 'sequent/core/event_store'

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
    #     Sequent.configuration.event_store = Sequent::Test::CommandHandlerHelpers::FakeEventStore.new
    #     Sequent.configuration.command_handlers = [] # add your command handlers here
    #     Sequent.configuration.event_handlers = [] # add you event handlers (eg, workflows) here
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
        extend Forwardable

        def initialize
          @event_streams = {}
          @all_events = {}
          @stored_events = []
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

        def commit_events(_, streams_with_events)
          streams_with_events.each do |event_stream, events|
            serialized = serialize_events(events)
            @event_streams[event_stream.aggregate_id] = event_stream
            @all_events[event_stream.aggregate_id] ||= []
            @all_events[event_stream.aggregate_id] += serialized
            @stored_events += serialized
          end
          publish_events(streams_with_events.flat_map { |_, events| events })
        end

        def publish_events(events)
          Sequent.configuration.event_publisher.publish_events(events)
        end

        def given_events(events)
          commit_events(nil, to_event_streams(events))
          @stored_events = []
        end

        def stream_exists?(aggregate_id)
          @event_streams.has_key?(aggregate_id)
        end

        def events_exists?(aggregate_id)
          @event_streams[aggregate_id].present?
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
                  aggregate_type = aggregate_type_for_event(event)
                  raise "cannot find aggregate type associated with creation event #{event}, did you include an event handler in your aggregate for this event?" unless aggregate_type
                  Sequent::Core::EventStream.new(aggregate_type: aggregate_type.name, aggregate_id: aggregate_id)
                end
            end
            [event_stream, [event]]
          end
        end

        def aggregate_type_for_event(event)
          @event_to_aggregate_type ||= ThreadSafe::Cache.new
          @event_to_aggregate_type.fetch_or_store(event.class) do |klass|
            Sequent::Core::AggregateRoots.all.find { |x| x.message_mapping.has_key?(klass.name) }
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
        Sequent.configuration.event_store.given_events(events.flatten(1))
      end

      def when_command command
        Sequent.configuration.command_service.execute_commands command
      end

      def then_events(*expected_events)
        expected_classes = expected_events.flatten(1).map { |event| event.class == Class ? event : event.class }
        expect(Sequent.configuration.event_store.stored_events.map(&:class)).to eq(expected_classes)

        Sequent.configuration.event_store.stored_events.zip(expected_events.flatten(1)).each_with_index do |(actual, expected), index|
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
