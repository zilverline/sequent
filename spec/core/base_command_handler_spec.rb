require 'spec_helper'

describe Sequent::Core::BaseCommandHandler do
  describe '.inherited' do
    it 'registers itself with Sequent::Core::CommandService' do
      command_handler = Class.new(Sequent::Core::BaseCommandHandler) do
      end
      expect(Sequent::Core::CommandService.instance.configuration.command_handler_classes).to include command_handler
    end
  end
end
