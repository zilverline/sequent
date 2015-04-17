require 'spec_helper'

describe Sequent::Core::EventStore do
  context ".configure" do

    it "can be configured using a ActiveRecord class" do
      Sequent.configure do |config|
        config.record_class = :foo
      end
      expect(Sequent.configuration.record_class).to eq :foo
    end

    it "can be configured with event_handlers" do
      event_handler_class = Class.new
      Sequent.configure do |config|
        config.event_handlers = [event_handler_class]
      end
      expect(Sequent.configuration.all_event_handlers).to eq [event_handler_class]
    end

    it 'can be configured multiple times' do
      foo = Class.new
      bar = Class.new
      Sequent.configure do |config|
        config.event_handlers = [foo]
      end
      expect(Sequent.configuration.all_event_handlers).to eq [foo]
      Sequent.configure do |config|
        config.event_handlers << bar
      end
      expect(Sequent.configuration.all_event_handlers).to eq [foo, bar]
    end
  end
end
