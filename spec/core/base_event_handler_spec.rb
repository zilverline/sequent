require 'spec_helper'

describe Sequent::Core::BaseEventHandler do
  describe '.inherited' do
    it 'registers itself with Sequent::Core::EventStore' do
      event_handler = Class.new(Sequent::Core::BaseEventHandler) do
      end
      expect(Sequent.configuration.all_event_handlers).to include event_handler
    end
  end
end
