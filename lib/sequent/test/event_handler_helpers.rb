module Sequent
  module Test
    ##
    # Use in tests
    #
    # This provides a nice DSL for testing your event handlers.
    # E.g.
    #
    # when_event UserWasRegistered.new(args)
    # then_commands SendWelcomeEmail.new(args)
    #
    # Example for Rspec config
    #
    # RSpec.configure do |config|
    #   config.include Sequent::Test::WorkflowHelpers
    # end
    #
    # Then in a spec
    #
    # describe SendWelcomeMailWorkflow do
    #   let(:workflow) { SendWelcomeMailWorkflow.new }
    #
    #   it "sends a welcome mail" do
    #     when_event UserWasRegistered.new(args)
    #     then_commands SendWelcomeEmail.new(args)
    #   end
    # end
    module WorkflowHelpers

      class FakeTransactionProvider
        def initialize
          @after_commit_blocks = []
        end

        def transactional
          yield
          @after_commit_blocks.each(&:call)
        end

        def after_commit(&block)
          @after_commit_blocks << block
        end
      end

      class FakeCommandService
        attr_reader :recorded_commands

        def initialize
          @recorded_commands = []
        end

        def execute_commands(*commands)
          @recorded_commands += commands
        end
      end

      def then_events(*expected_events)
        expected_classes = expected_events.flatten(1).map { |event| event.class == Class ? event : event.class }
        expect(Sequent.configuration.event_store.stored_events.map(&:class)).to eq(expected_classes)

        Sequent.configuration.event_store.stored_events.zip(expected_events.flatten(1)).each do |actual, expected|
          next if expected.class == Class
          expect(Sequent::Core::Oj.strict_load(Sequent::Core::Oj.dump(actual.payload))).to eq(Sequent::Core::Oj.strict_load(Sequent::Core::Oj.dump(expected.payload))) if expected
        end
      end

      def then_no_events
        then_events
      end

      def when_event(event)
        workflow.handle_message event
      end

      def then_commands(*commands)
        recorded = fake_command_service.recorded_commands
        expect(recorded.map(&:class)).to eq(commands.flatten(1).map(&:class))
        expect(fake_command_service.recorded_commands).to eq(commands.flatten(1))
        expect(recorded).to all(be_valid)
      end

      def self.included(spec)
        spec.let(:fake_command_service) { FakeCommandService.new }
        spec.let(:fake_transaction_provider) { FakeTransactionProvider.new }
        spec.before do
          Sequent.configure do |c|
            c.command_service = fake_command_service
            c.transaction_provider = fake_transaction_provider
          end
        end
      end
    end
  end
end
