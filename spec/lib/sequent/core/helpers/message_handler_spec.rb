# frozen_string_literal: true

require 'spec_helper'

describe Sequent::Core::Helpers::MessageHandler do
  class MessageHandlerEvent < Sequent::Event
    def initialize
      super(aggregate_id: '1', sequence_number: 1)
    end
  end

  class MessageHandlerEventOtherEvent < Sequent::Event; end

  class MyHandler
    include Sequent::Core::Helpers::MessageHandler

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
end
