require 'spec_helper'

describe Sequent::Core::BaseCommandHandler do
  describe '.inherited' do
    it 'registers itself with Sequent::Core::CommandService' do
      command_handler = Class.new(Sequent::Core::BaseCommandHandler)
      expect(Sequent.configuration.all_command_handlers).to include command_handler
    end
  end
end
