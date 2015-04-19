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
          @all_events = []
          @stored_events = []
        end

        def load_events(aggregate_id)
          deserialize_events(@all_events).select { |event| aggregate_id == event.aggregate_id }
        end

        def stored_events
          deserialize_events(@stored_events)
        end

        def commit_events(_, events)
          serialized = serialize_events(events)
          @all_events += serialized
          @stored_events += serialized
        end

        def given_events(events)
          @all_events += serialize_events(events)
          @stored_events = []
        end

        private
        def serialize_events(events)
          events.map { |event| [event.class.name.to_sym, Oj.dump(event)] }
        end

        def deserialize_events(events)
          events.map do |type, json|
            Class.const_get(type).deserialize_from_json(Oj.strict_load(json, {}))
          end
        end

      end

      def given_events *events
        raise ArgumentError.new("events can not be nil") if events.compact.empty?
        @event_store.given_events(events)
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
          Oj.strict_load(Oj.dump(actual.payload), {}).should == Oj.strict_load(Oj.dump(expected.payload), {}) if expected
        end
      end

      def then_no_events
        then_events
      end

    end

  end
end
