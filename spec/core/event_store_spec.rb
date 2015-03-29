require 'spec_helper'

describe Sequent::Core::EventStore do
  context ".configure" do

    it "can be configured using a ActiveRecord class" do
      Sequent::Core::EventStore.configure do |config|
        config.record_class = :foo
      end
      expect(Sequent::Core::EventStore.configuration.record_class).to eq :foo
    end

    it "can be configured with event_handlers" do
      Sequent::Core::EventStore.configure do |config|
        config.event_handlers = [:event_handler]
      end
      expect(Sequent::Core::EventStore.configuration.event_handlers).to eq [:event_handler]
    end
  end
end
