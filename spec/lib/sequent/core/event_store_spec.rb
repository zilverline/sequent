require 'spec_helper'

describe Sequent::Core::EventStore do
  context ".configure" do

    it "can be configured using a ActiveRecord class" do
      Sequent::Core::EventStore.configure do |config|
        config.record_class = :foo
      end
      expect(Sequent::Core::EventStore.instance.configuration.record_class).to eq :foo
    end

    it "can be configured with event_handlers" do
      event_handler_class = Class.new
      Sequent::Core::EventStore.configure do |config|
        config.event_handler_classes = [event_handler_class]
      end
      expect(Sequent::Core::EventStore.instance.configuration.event_handler_classes).to eq [event_handler_class]
    end

    it 'can be configured multiple times' do
      foo = Class.new
      bar = Class.new
      Sequent::Core::EventStore.configure do |config|
        config.event_handler_classes = [foo]
      end
      expect(Sequent::Core::EventStore.instance.configuration.event_handler_classes).to eq [foo]
      Sequent::Core::EventStore.configure do |config|
        config.event_handler_classes << bar
      end
      expect(Sequent::Core::EventStore.instance.configuration.event_handler_classes).to eq [foo, bar]
    end
  end
end
