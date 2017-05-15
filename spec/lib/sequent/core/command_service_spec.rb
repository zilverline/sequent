require 'spec_helper'

class DummyCommand < Sequent::Core::Command

end

class DummyBaseCommand < Sequent::Core::BaseCommand
  attrs mandatory_string: String
  validates_presence_of :mandatory_string
end

class NotHandledCommand < Sequent::Core::Command; end

class WithIntegerCommand < Sequent::Core::BaseCommand
  attrs value: Integer
end

class TestCommandHandler < Sequent::Core::BaseCommandHandler
  def initialize(*args)
    reset
    super(*args)
  end

  def reset
    @@called = nil
  end

  def called
    @@called
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
    command_service.execute_commands(NotHandledCommand.new(aggregate_id: "1"))
    expect(command_handler.called).to be_nil
  end

  it "calls a command handler when it does handle a certain command" do
    command_service.execute_commands(DummyCommand.new(aggregate_id: "1"))
    expect(command_handler.called).to eq "DummyCommand"
  end

  it "raises a CommandNotValid for invalid commands" do
    expect { command_service.execute_commands(DummyBaseCommand.new) }.to raise_error(Sequent::Core::CommandNotValid)
  end

  it "always clear repository after execute" do
    expect { command_service.execute_commands(DummyBaseCommand.new) }.to raise_error(Sequent::Core::CommandNotValid)
    expect(Thread.current[Sequent::Core::AggregateRepository::AGGREGATES_KEY]).to be_nil
  end

  context "command value parsing" do
    it "parses the values in the command if it is valid" do
      command_service.execute_commands(WithIntegerCommand.new(aggregate_id: "1", value: "2"))
      expect(command_handler.called.value).to eq 2
    end

    it 'removes leading zeros if it is valid' do
      command_service.execute_commands(WithIntegerCommand.new(aggregate_id: "1", value: "02"))
      expect(command_handler.called.value).to eq 2
    end

    it "does not parse values if the command is invalid" do
      command = WithIntegerCommand.new(value: "A")
      expect { command_service.execute_commands(command) }.to raise_error do |e|
        expect(e.errors[:value]).to eq ['is not a number']
      end
    end

    it "does not removes leading zeros if command is invalid" do
      command = WithIntegerCommand.new(aggregate_id: "1", value: "0x")
      expect { command_service.execute_commands(command) }.to raise_error do |e|
        expect(e.errors[:value]).to eq ['is not a number']
      end
    end

    it "does not removes leading zeros when using hexadecimal values" do
      command = WithIntegerCommand.new(aggregate_id: "1", value: "0x10")
      expect { command_service.execute_commands(command) }.to raise_error do |e|
        expect(e.errors[:value]).to eq ['is not a number']
      end
    end
  end
end
