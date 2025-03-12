# frozen_string_literal: true

require 'thread_safe'
require 'sequent/core/event_store'
require 'rspec'

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
    # Given events are applied against the Aggregate so need to represent a correct
    # sequence of events.
    #
    # When a command is executed all generated events are captured and can be
    # retrieved using `stored_events` or tested using `then_events`.
    #
    # The `then_events` expects one class, expected event, or RSpec
    # matcher for each generated event, in the same order.  Example
    # for Rspec config. When a class is passed, only the type of the
    # generated event is tested. When an expected event is passed only
    # the *payload* is compared using the `have_same_payload_as`
    # matcher defined by this module (`aggregate_id`,
    # `sequence_number`, and `created_at` are *not* compared). When an
    # RSpec matcher is passed the actual event is matched against this
    # matcher, so you can use `eq` or `have_attributes` to do more
    # specific matching.
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

        def commit_events(_, streams_with_events)
          keys = @unique_keys.dup.delete_if do |_key, aggregate_id|
            streams_with_events.any? { |stream, _| aggregate_id == stream.aggregate_id }
          end
          @unique_keys = keys.merge(
            *streams_with_events.map do |stream, _|
              stream.unique_keys.to_h { |scope, key| [[scope, key], stream.aggregate_id] }
            end,
          ) do |_key, id_1, id_2|
            if id_1 != id_2
              stream, = streams_with_events.find { |s| s[0].aggregate_id == id_2 }
              fail Sequent::Core::AggregateKeyNotUniqueError,
                   "duplicate unique key value for aggregate #{stream.aggregate_type} #{stream.aggregate_id}"
            end
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

        def stream_exists?(aggregate_id)
          @event_streams.key?(aggregate_id)
        end

        def events_exists?(aggregate_id)
          @event_streams[aggregate_id].present?
        end

        def position_mark
          @stored_events.length
        end

        def load_events_since_marked_position(mark)
          [deserialize_events(@stored_events[mark..]), position_mark]
        end

        def event_streams_enumerator(aggregate_type: nil, group_size: 100)
          @event_streams
            .values
            .select { |es| aggregate_type.nil? || es.aggregate_type == aggregate_type }
            .sort_by { |es| [es.events_partition_key, es.aggregate_id] }
            .map(&:aggregate_id)
            .each_slice(group_size)
        end

        private

        def serialize_events(events)
          events.map { |event| [event.class.name, Sequent::Core::Oj.dump(event)] }
        end

        def deserialize_events(events)
          events.map do |type, json|
            Class.const_get(type).deserialize_from_json(Sequent::Core::Oj.strict_load(json))
          end
        end
      end

      RSpec::Matchers.define :have_same_payload_as do |expected|
        match do |actual|
          actual_hash = Sequent::Core::Oj.strict_load(Sequent::Core::Oj.dump(actual.payload))
          expected_hash = Sequent::Core::Oj.strict_load(Sequent::Core::Oj.dump(expected.payload))
          values_match? expected_hash, actual_hash
        end

        description do
          expected.to_s
        end

        diffable
      end

      def given_events(*events)
        Sequent.configuration.event_store.commit_events(
          Sequent::Core::BaseCommand.new,
          to_event_streams(events.flatten(1)),
        )
      end

      def when_command(command)
        @helpers_events_position_mark = Sequent.configuration.event_store.position_mark
        Sequent.configuration.command_service.execute_commands command
      end

      def then_events(*expected_events)
        matchers = expected_events.flatten(1).map do |expected|
          if expected.is_a?(Sequent::Core::Event)
            have_same_payload_as(expected)
          else
            expected
          end
        end

        expect(stored_events).to match(matchers)
      end

      def then_no_events
        then_events
      end

      def stored_events
        Sequent.configuration.event_store.load_events_since_marked_position(@helpers_events_position_mark)[0]
      end

      private

      def to_event_streams(uncommitted_events)
        # Specs use a simple list of given events.
        # We need a mapping from StreamRecord to the associated events for the event store.
        uncommitted_events.group_by(&:aggregate_id).map do |aggregate_id, new_events|
          _, existing_events = Sequent.configuration.event_store.load_events(aggregate_id) || [nil, []]
          all_events = existing_events + new_events
          aggregate_type = aggregate_type_for_event(all_events[0])
          unless aggregate_type
            fail <<~EOS
              Cannot find aggregate type associated with creation event #{all_events[0]}, did you include an event handler in your aggregate for this event?
            EOS
          end

          aggregate = aggregate_type.load_from_history(nil, all_events)
          [aggregate.event_stream, new_events]
        end
      end

      def aggregate_type_for_event(event)
        @helpers_event_to_aggregate_type ||= ThreadSafe::Cache.new
        @helpers_event_to_aggregate_type.fetch_or_store(event.class) do |klass|
          Sequent::Core::AggregateRoot.descendants.find { |x| x.message_mapping.key?(klass) }
        end
      end
    end
  end
end
