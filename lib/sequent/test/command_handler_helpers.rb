# frozen_string_literal: true

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
    # when_command PayInvoiceCommand.new(args)
    # then_events InvoicePaidEvent.new(args)
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
          @unique_keys = {}
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
          keys = @unique_keys.dup.delete_if do |_key, aggregate_id|
            streams_with_events.any? { |stream, _| aggregate_id == stream.aggregate_id }
          end
          @unique_keys = keys.merge(
            *streams_with_events.map do |stream, _|
              stream.unique_keys.to_h { |scope, key| [[scope, key], stream.aggregate_id] }
            end,
          ) do |_key, id_1, id_2|
            fail Sequent::Core::AggregateKeyNotUniqueError if id_1 != id_2
          end

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
          @event_streams.key?(aggregate_id)
        end

        def events_exists?(aggregate_id)
          @event_streams[aggregate_id].present?
        end

        private

        def to_event_streams(uncommitted_events)
          # Specs use a simple list of given events.
          # We need a mapping from StreamRecord to the associated events for the event store.
          uncommitted_events.group_by(&:aggregate_id).values.map do |events|
            aggregate_type = aggregate_type_for_event(events[0])
            unless aggregate_type
              fail <<~EOS
                Cannot find aggregate type associated with creation event #{events[0]}, did you include an event handler in your aggregate for this event?
              EOS
            end

            aggregate = aggregate_type.load_from_history(nil, events)
            [aggregate.event_stream, events]
          end
        end

        def aggregate_type_for_event(event)
          @event_to_aggregate_type ||= ThreadSafe::Cache.new
          @event_to_aggregate_type.fetch_or_store(event.class) do |klass|
            Sequent::Core::AggregateRoot.descendants.find { |x| x.message_mapping.key?(klass) }
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

      def given_events(*events)
        Sequent.configuration.event_store.given_events(events.flatten(1))
      end

      def when_command(command)
        Sequent.configuration.command_service.execute_commands command
      end

      def then_events(*expected_events)
        expected_classes = expected_events.flatten(1).map { |event| event.instance_of?(Class) ? event : event.class }
        expect(Sequent.configuration.event_store.stored_events.map(&:class)).to eq(expected_classes)

        Sequent
          .configuration
          .event_store
          .stored_events
          .zip(expected_events.flatten(1))
          .each_with_index do |(actual, expected), index|
            next if expected.instance_of?(Class)

            actual_hash = Sequent::Core::Oj.strict_load(Sequent::Core::Oj.dump(actual.payload))
            expected_hash = Sequent::Core::Oj.strict_load(Sequent::Core::Oj.dump(expected.payload))
            next unless expected

            # rubocop:disable Layout/LineLength
            expect(actual_hash)
              .to eq(expected_hash),
                  "#{index + 1}th Event of type #{actual.class} not equal\nexpected: #{expected_hash.inspect}\n     got: #{actual_hash.inspect}"
            # rubocop:enable Layout/LineLength
          end
      end

      def then_no_events
        then_events
      end
    end
  end
end
