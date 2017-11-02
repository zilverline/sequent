require 'spec_helper'

describe Sequent::Configuration do
  let(:instance) { described_class.instance }

  context Sequent::Core::BaseCommandHandler do
    class SpecHandler < Sequent::Core::BaseCommandHandler
      def repository
        super
      end
    end
    let(:spec_handler) { SpecHandler.new }

    before :each do
      Sequent.configure do |config|
        config.command_handlers << spec_handler
      end
    end

    it 'adds the default repository to all command handlers' do
      expect(spec_handler.repository).to_not be_nil
      expect(spec_handler.repository).to eq Sequent.configuration.aggregate_repository
    end

    it 'notifies command handlers when event_store changes' do
      new_event_store = double
      Sequent.configuration.event_store = new_event_store
      expect(spec_handler.repository).to eq Sequent.configuration.aggregate_repository
    end
  end

end
