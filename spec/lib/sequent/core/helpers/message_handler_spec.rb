# frozen_string_literal: true

require 'spec_helper'

describe Sequent::Core::Helpers::MessageHandler do
  class BaseEvent < Sequent::Event
    def initialize
      super(aggregate_id: '1', sequence_number: 1)
    end
  end

  class MessageHandlerEvent < BaseEvent
  end

  class MessageHandlerEventOtherEvent < Sequent::Event; end

  class MyHandler
    include Sequent::Core::Helpers::MessageHandler

    message_base_class Sequent::Event

    attr_reader :first_block_called, :last_block_called

    on MessageHandlerEvent, MessageHandlerEventOtherEvent do
      @first_block_called = true
    end

    on MessageHandlerEvent do
      @last_block_called = true
    end
  end

  let(:handler) { MyHandler.new }

  it 'executes all defined blocks' do
    handler.handle_message(MessageHandlerEvent.new)

    expect(handler.first_block_called).to be_truthy
    expect(handler.last_block_called).to be_truthy
  end

  context do
    module MyEventModule; end

    class MyEventWithModule < BaseEvent
      include MyEventModule
    end

    class OtherEventWithModule < BaseEvent
      include MyEventModule
    end

    class MySimpleEvent < BaseEvent; end
    class MyEventSuperclass < BaseEvent; end
    class MyEventSubclass < MyEventSuperclass; end

    class SomeHandler
      include Sequent::Core::Helpers::MessageHandler

      message_base_class Sequent::Event

      attr_reader :called_blocks

      def initialize
        @called_blocks = []
      end

      on MyEventModule do
        @called_blocks.push(MyEventModule)
      end

      on MyEventWithModule do
        @called_blocks.push(MyEventWithModule)
      end

      on OtherEventWithModule do
        @called_blocks.push(OtherEventWithModule)
      end

      on MySimpleEvent do
        @called_blocks.push(MySimpleEvent)
      end

      on MyEventSuperclass do
        @called_blocks.push(MyEventSuperclass)
      end

      on MyEventSubclass do
        @called_blocks.push(MyEventSubclass)
      end
    end

    let(:handler) { SomeHandler.new }

    context 'given a module is registered with an on block' do
      context 'and a message that includes the module that is handled' do
        it 'executes matching defined blocks' do
          handler.handle_message(MyEventWithModule.new)

          expect(handler.called_blocks).to eq([MyEventModule, MyEventWithModule])
        end
      end
    end

    context 'given a super class is registered with an on block' do
      context 'and a message that extends from that class' do
        it 'executes matching defined blocks' do
          handler.handle_message(MyEventSubclass.new)

          expect(handler.called_blocks).to eq([MyEventSuperclass, MyEventSubclass])
        end
      end
    end

    context 'given a message which does not descend from message_base_class' do
      class SomeMessage; end

      it 'fails' do
        expect { SomeHandler.on(SomeMessage) }.to raise_error(
          Sequent::Core::Helpers::MessageHandler::ConfigurationError,
          "Expected 'SomeMessage' to be a descendant from 'Sequent::Core::Event'",
        )
      end
    end

    context 'given no configured message_base_class' do
      class HandlerWithoutMessageBaseClass
        include Sequent::Core::Helpers::MessageHandler
      end

      it 'fails' do
        expect { HandlerWithoutMessageBaseClass.on(MyEventModule) }.to raise_error(
          Sequent::Core::Helpers::MessageHandler::ConfigurationError,
          "Missing message base class configuration for 'HandlerWithoutMessageBaseClass', " \
          'please configure it using `message_base_class`',
        )
      end
    end

    describe '.message_base_class' do
      class AnotherHandler
        include Sequent::Core::Helpers::MessageHandler
      end

      subject { AnotherHandler.message_base_class(message_base_class) }

      around do |example|
        AnotherHandler.reset_message_base_class

        example.run
      ensure
        AnotherHandler.reset_message_base_class
      end

      context 'given an ActiveSupport::DescendantsTracker' do
        let(:message_base_class) { Sequent::Event }

        it 'sets the message base class' do
          subject

          expect(AnotherHandler.get_message_base_class).to eq(message_base_class)
        end
      end

      context 'given not an ActiveSupport::DescendantsTracker' do
        let(:message_base_class) { Object }

        it 'fails' do
          expect { subject }
            .to raise_error(
              ArgumentError,
              "'message_base_class' should be an ActiveSupport::DescendantsTracker",
            )
        end
      end

      context 'given nil' do
        let(:message_base_class) { nil }

        it 'fails' do
          expect { subject }
            .to raise_error(
              ArgumentError,
              "'message_base_class' should be an ActiveSupport::DescendantsTracker",
            )
        end
      end
    end
  end
end
