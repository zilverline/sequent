require 'spec_helper'

class DummyCommand < Sequent::Core::Command

end

class DummyBaseCommand < Sequent::Core::BaseCommand
  attrs mandatory_string: String
  validates_presence_of :mandatory_string
end

describe Sequent::Core::CommandService do

  let(:event_store) { double }
  let(:foo_handler_class) { double }
  let(:foo_handler) { double }
  let(:command) { DummyCommand.new(aggregate_id: "1") }

  let(:command_service) do
    Sequent::Core::CommandService.new(
      event_store,
      [foo_handler_class]
    )
  end

  before :each do
    expect(foo_handler_class).to receive(:new).and_return(foo_handler)
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

end
