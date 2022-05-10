# frozen_string_literal: true

require 'spec_helper'

describe Sequent::Core::Helpers::MessageHandler do
  class BaseMessageHandlerEvent < Sequent::Event
    def initialize
      super(aggregate_id: '1', sequence_number: 1)
    end
  end

  class MessageHandlerEvent < BaseMessageHandlerEvent; end

  class MessageHandlerEventOtherEvent < Sequent::Event; end

  class MyHandler
    include Sequent::Core::Helpers::MessageHandler

    attr_reader :first_block_called, :last_block_called

    FIRST_HANDLER = ->(_event) { @first_block_called = true }
    LAST_HANDLER = ->(_event) { @last_block_called = true }

    on MessageHandlerEvent, MessageHandlerEventOtherEvent, &FIRST_HANDLER

    on MessageHandlerEvent, &LAST_HANDLER
  end

  let(:handler) { MyHandler.new }

  it 'executes all defined blocks' do
    handler.handle_message(MessageHandlerEvent.new)

    expect(handler.first_block_called).to be_truthy
    expect(handler.last_block_called).to be_truthy
  end

  describe '.message_mapping' do
    subject { MyHandler.message_mapping }

    it 'returns a mapping of message classes to handlers' do
      expect(subject).to eq(
        MessageHandlerEvent => Set[MyHandler::FIRST_HANDLER, MyHandler::LAST_HANDLER],
        MessageHandlerEventOtherEvent => Set[MyHandler::FIRST_HANDLER],
      )
    end

    context 'given a non-class/module argument' do
      module EventModule; end
      class OtherHandlerEvent < BaseMessageHandlerEvent
        include EventModule
      end

      class OtherHandler
        include Sequent::Core::Helpers::MessageHandler

        HANDLER = ->(_event) {}

        on is_a(EventModule), &HANDLER
      end

      subject { OtherHandler.message_mapping }

      it 'only returns a mapping of message classes to handlers' do
        expect(subject).to be_empty
      end
    end
  end

  describe Sequent::Core::Helpers::MessageHandler::OnArgumentsValidator do
    describe '.validate_arguments!' do
      subject { Sequent::Core::Helpers::MessageHandler::OnArgumentsValidator.validate_arguments!(*args) }

      context 'given no arguments' do
        let(:args) { [] }

        it 'fails' do
          expect { subject }.to raise_error(ArgumentError, "Must provide at least one argument to 'on'")
        end
      end

      context 'given unique arguments' do
        let(:args) { %i[a b] }

        it 'does not fail' do
          expect { subject }.to_not raise_error
        end
      end

      context 'given duplicate arguments' do
        let(:args) { %i[a b a b c] }

        it 'fails' do
          expect { subject }.to raise_error(ArgumentError, "Arguments to 'on' must be unique, duplicates: a, b")
        end
      end
    end
  end
end
