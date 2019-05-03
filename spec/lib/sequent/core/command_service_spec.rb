require 'spec_helper'

class TestCommandHandler < Sequent::CommandHandler
  class DummyCommand < Sequent::Core::Command; end

  class DummyBaseCommand < Sequent::Core::BaseCommand
    attrs mandatory_string: String
    validates_presence_of :mandatory_string
  end

  class NotHandledCommand < Sequent::Core::Command; end

  class WithIntegerCommand < Sequent::Core::BaseCommand
    attrs value: Integer
  end

  class CommandWithSecret < Sequent::Core::BaseCommand
    attrs password: Sequent::Secret
  end

  def initialize(*args)
    reset
    super(*args)
  end

  def reset
    @@called = nil
    @@password = nil
  end

  def called
    @@called
  end

  def password
    @@password
  end

  on DummyCommand do
    @@called = 'DummyCommand'
  end

  on DummyBaseCommand do
    @@called = 'DummyBaseCommand'
  end

  on WithIntegerCommand do |command|
    @@called = command
  end

  on CommandWithSecret do |command|
    @@password = command.password
  end
end

describe Sequent::Core::CommandService do

  let(:event_store) { double }

  let(:command_handler) { TestCommandHandler.new }

  let(:command_service) do
    Sequent.configure do |config|
      config.command_handlers = [command_handler]
    end
    Sequent.configuration.command_service
  end

  it "does not break when it does not handle a certain command" do
    command_service.execute_commands(TestCommandHandler::NotHandledCommand.new(aggregate_id: "1"))
    expect(command_handler.called).to be_nil
  end

  it "calls a command handler when it does handle a certain command" do
    command_service.execute_commands(TestCommandHandler::DummyCommand.new(aggregate_id: "1"))
    expect(command_handler.called).to eq "DummyCommand"
  end

  it "raises a CommandNotValid for invalid commands" do
    expect { command_service.execute_commands(TestCommandHandler::DummyBaseCommand.new) }.to raise_error(Sequent::Core::CommandNotValid)
  end

  it "always clear repository after execute" do
    expect { command_service.execute_commands(TestCommandHandler::DummyBaseCommand.new) }.to raise_error(Sequent::Core::CommandNotValid)
    expect(Thread.current[Sequent::Core::AggregateRepository::AGGREGATES_KEY]).to be_nil
  end

  context "command value parsing" do
    it 'parses secrets using bcrypt when executing' do
      command_service.execute_commands(TestCommandHandler::CommandWithSecret.new(password: 'secret'))

      expect(Sequent::Secret.verify_secret(command_handler.password.value, 'secret')).to be_truthy
      expect(command_handler.password.verify_secret('secret')).to be_truthy
    end

    it "parses the values in the command if it is valid" do
      command_service.execute_commands(TestCommandHandler::WithIntegerCommand.new(aggregate_id: "1", value: "2"))
      expect(command_handler.called.value).to eq 2
    end

    it 'removes leading zeros if it is valid' do
      command_service.execute_commands(TestCommandHandler::WithIntegerCommand.new(aggregate_id: "1", value: "02"))
      expect(command_handler.called.value).to eq 2
    end

    it "does not parse values if the command is invalid" do
      command = TestCommandHandler::WithIntegerCommand.new(value: "A")
      expect { command_service.execute_commands(command) }.to raise_error do |e|
        expect(e.errors[:value]).to eq ['is not a number']
      end
    end

    it "does not removes leading zeros if command is invalid" do
      command = TestCommandHandler::WithIntegerCommand.new(aggregate_id: "1", value: "0x")
      expect { command_service.execute_commands(command) }.to raise_error do |e|
        expect(e.errors[:value]).to eq ['is not a number']
      end
    end

    it "does not removes leading zeros when using hexadecimal values" do
      command = TestCommandHandler::WithIntegerCommand.new(aggregate_id: "1", value: "0x10")
      expect { command_service.execute_commands(command) }.to raise_error do |e|
        expect(e.errors[:value]).to eq ['is not a number']
      end
    end
  end

  context 'commands triggered by workflows' do
    let(:handler_1) {
      Class.new(Sequent::CommandHandler) do
        def ping_command
          @ping_command
        end

        def create_command
          @create_command
        end

        on Sequent::Fixtures::CreateTestAggregate do |command|
          @create_command = command
          aggregate = Sequent::Fixtures::TestAggregateRoot.new(command.aggregate_id)
          Sequent.aggregate_repository.add_aggregate(aggregate)
        end

        on Sequent::Fixtures::PingTestAggregate do |command|
          @ping_command = command
        end
      end.new
    }

    let(:handler_2) {
      Class.new(Sequent::CommandHandler) do
        def notify_command
          @notify_command
        end

        on Sequent::Fixtures::NotifyTestAggregateCreated do |command|
          @notify_command = command
        end
      end.new
    }

    let(:workflow) {
      Class.new(Sequent::Workflow) do
        on Sequent::Fixtures::TestAggregateCreated do |event|
          Sequent.command_service.execute_commands Sequent::Fixtures::NotifyTestAggregateCreated.new(
            aggregate_id: Sequent.new_uuid,
            test_aggregate_id: event.aggregate_id,
          )
        end
      end
    }

    before :each do
      Sequent.configure do |config|
        config.command_handlers = [
          handler_1,
          handler_2,
        ]
        config.event_handlers = [
          workflow.new
        ]
      end
    end

    it 'only registers the current event when executed' do
      aggregate_id = Sequent.new_uuid
      Sequent.command_service.execute_commands(
        Sequent::Fixtures::CreateTestAggregate.new(
          aggregate_id: aggregate_id
        ),
        Sequent::Fixtures::PingTestAggregate.new(
          aggregate_id: aggregate_id,
          message: 'ping',
        )
      )

      # these commands should not be enriched with the event_aggregate_id
      # since they are not called via the workflow
      expect(handler_1.create_command.aggregate_id).to eq aggregate_id
      expect(handler_1.create_command.event_aggregate_id).to be_nil
      expect(handler_1.create_command.event_sequence_number).to be_nil

      expect(handler_1.ping_command.aggregate_id).to eq aggregate_id
      expect(handler_1.ping_command.message).to eq 'ping'
      expect(handler_1.ping_command.event_aggregate_id).to be_nil
      expect(handler_1.ping_command.event_sequence_number).to be_nil

      # this handler is executed via the workflow so they should have
      # the aggregate_id and sequence number of the event that
      # triggered the command
      expect(handler_2.notify_command.aggregate_id).to_not eq aggregate_id
      expect(handler_2.notify_command.test_aggregate_id).to eq aggregate_id
      expect(handler_2.notify_command.event_aggregate_id).to eq aggregate_id
      expect(handler_2.notify_command.event_sequence_number).to eq 1

      Sequent.command_service.execute_commands(
        Sequent::Fixtures::PingTestAggregate.new(
          aggregate_id: aggregate_id,
          message: 'pong',
        )
      )

      # executing a commands afterward should not have the event_aggregate_id
      # this ensure no state is left behind
      expect(handler_1.ping_command.aggregate_id).to eq aggregate_id
      expect(handler_1.ping_command.message).to eq 'pong'
      expect(handler_1.ping_command.event_aggregate_id).to be_nil
      expect(handler_1.ping_command.event_sequence_number).to be_nil
    end

    context 'super nested workflows' do
      let(:handler_2) {
        Class.new(Sequent::CommandHandler) do
          def notify_command
            @notify_command
          end

          def ping_received_command
            @ping_received_command
          end

          on Sequent::Fixtures::NotifyTestAggregateCreated do |command|
            @notify_command = command
            aggregate = Sequent.aggregate_repository.load_aggregate(command.test_aggregate_id)
            aggregate.ping('notify created!')
          end

          on Sequent::Fixtures::NotifyTestAggregatePingReceived do |command|
            @ping_received_command = command
          end
        end.new
      }

      let(:workflow) {
        Class.new(Sequent::Workflow) do
          on Sequent::Fixtures::TestAggregateCreated do |event|
            Sequent.command_service.execute_commands Sequent::Fixtures::NotifyTestAggregateCreated.new(
              aggregate_id: Sequent.new_uuid,
              test_aggregate_id: event.aggregate_id,
            )
          end

          on Sequent::Fixtures::TestAggregatePinged do |event|
            Sequent.command_service.execute_commands Sequent::Fixtures::NotifyTestAggregatePingReceived.new(
              aggregate_id: Sequent.new_uuid,
              test_aggregate_id: event.aggregate_id,
            )
          end
        end
      }

      it 'registers the correct event_aggregate_ids for super nested workflows' do
        aggregate_id = Sequent.new_uuid
        Sequent.command_service.execute_commands(
          Sequent::Fixtures::CreateTestAggregate.new(
            aggregate_id: aggregate_id
          )
        )

        expect(handler_2.notify_command.aggregate_id).to_not eq aggregate_id
        expect(handler_2.notify_command.test_aggregate_id).to eq aggregate_id
        expect(handler_2.notify_command.event_aggregate_id).to eq aggregate_id
        expect(handler_2.notify_command.event_sequence_number).to eq 1

        expect(handler_2.ping_received_command.aggregate_id).to_not eq aggregate_id
        expect(handler_2.ping_received_command.test_aggregate_id).to eq aggregate_id
        expect(handler_2.ping_received_command.event_aggregate_id).to eq aggregate_id
        expect(handler_2.ping_received_command.event_sequence_number).to eq 2
      end
    end
  end
end
