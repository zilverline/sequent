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

        def given_events(streams_with_events)
          commit_events(nil, streams_with_events)
          @stored_events = []
        end

        private

        def serialize_events(events)
          events.map { |event| [event.class.name, Sequent::Core::Oj.dump(event)] }
        end

        def deserialize_events(events)
          events.map do |type, json|
            Sequent::Core::Helpers::constant_get!(type).deserialize_from_json(Sequent::Core::Oj.strict_load(json))
          end
        end

      end

      def given_streams_with_events *streams_with_events
        @event_store.given_events(streams_with_events)
      end

      def when_command command
        raise "@command_handler is mandatory when using the #{self.class}" unless @command_handler
        raise "Command handler #{@command_handler} cannot handle command #{command}, please configure the command type (forgot an include in the command class?)" unless @command_handler.handles_message?(command)
        @command_handler.handle_message(command)
        @repository.commit(command)
      end

      def then_events *events
        @event_store.stored_events.map(&:class).should == events.map(&:class)
        @event_store.stored_events.zip(events).each do |actual, expected|
          Sequent::Core::Oj.strict_load(Sequent::Core::Oj.dump(actual.payload)).should == Sequent::Core::Oj.strict_load(Sequent::Core::Oj.dump(expected.payload)) if expected
        end
      end

      def then_no_events
        then_events
      end

    end

  end
end
