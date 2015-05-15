require 'spec_helper'

class DummyCommand < Sequent::Core::Command

end

class DummyBaseCommand < Sequent::Core::BaseCommand
  attrs mandatory_string: String
  validates_presence_of :mandatory_string
end

describe Sequent::Core::CommandService do

  let(:event_store) { double }
  let(:foo_handler) { double }
  let(:command) { DummyCommand.new(aggregate_id: "1") }

  let(:command_service) do
    Sequent.configure do |config|
      config.command_handlers = [foo_handler]
    end
    Sequent.configuration.command_service
  end

  it "does not call a command handler when it does not handle a certain command" do
    expect(foo_handler).to receive(:handles_message?).and_return(false)

    command_service.execute_commands(command)
  end

  it "calls a command handler when it does handle a certain command" do
    expect(foo_handler).to receive(:handles_message?).and_return(true)
    expect(foo_handler).to receive(:handle_message).with(command).and_return(true)

    command_service.execute_commands(command)
  end

  it "raises a CommandNotValid for invalid commands" do
    expect { command_service.execute_commands(DummyBaseCommand.new) }.to raise_error(Sequent::Core::CommandNotValid)
  end

  it "always clear repository after execute" do
    expect { command_service.execute_commands(DummyBaseCommand.new) }.to raise_error(Sequent::Core::CommandNotValid)
    expect(Thread.current[Sequent::Core::AggregateRepository::AGGREGATES_KEY]).to be_empty
  end

  context "command value parsing" do
    class WithIntegerCommand < Sequent::Core::BaseCommand
      attrs value: Integer
    end

    it "parses the values in the command if it is valid" do
      command = WithIntegerCommand.new(aggregate_id: "1", value: "2")

      expect(foo_handler).to receive(:handles_message?).and_return(true)
      expect(foo_handler).to receive(:handle_message).with(
                               WithIntegerCommand.new(aggregate_id: "1", value: 2)
                             ).and_return(true)

      command_service.execute_commands(command)
    end

    it "does not parse values if the command is invalid" do
      command = WithIntegerCommand.new(value: "A")
      expect { command_service.execute_commands(command) }.to raise_error do |e|
                                                                expect(e.errors[:value]).to eq ['is not a number']
                                                              end
    end
  end
end
