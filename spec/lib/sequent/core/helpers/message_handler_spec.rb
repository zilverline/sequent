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

  describe Sequent::Core::Helpers::MessageHandler::OnArgumentCoercer do
    describe '.coerce_argument' do
      subject { Sequent::Core::Helpers::MessageHandler::OnArgumentCoercer.coerce_argment(arg) }

      class MyEvent < Sequent::Event; end
      module MyModule; end

      context 'given nil' do
        let(:arg) { nil }

        it 'fails' do
          expect { subject }.to raise_error(ArgumentError, "Argument to 'on' cannot be nil")
        end
      end

      context 'given a Class argument' do
        let(:arg) { MyEvent }

        it 'returns the argument wrapped in a MessageMatchers::ClassEquals' do
          expect(subject).to eq(Sequent::Core::Helpers::MessageMatchers::ClassEquals.new(expected_class: arg))
        end
      end

      context 'given a module argument' do
        let(:arg) { MyModule }

        it 'returns the argument wrapped in a MessageMatchers::ClassEquals' do
          expect(subject).to eq(Sequent::Core::Helpers::MessageMatchers::ClassEquals.new(expected_class: arg))
        end
      end

      context 'given the argument responds to :matches_message?' do
        let(:arg) { Sequent::Core::Helpers::MessageMatchers::IsA.new(expected_class: MyModule) }

        it 'returns that argument' do
          expect(subject).to eq(arg)
        end
      end

      context 'given something else' do
        let(:arg) { Object.new }

        it 'fails' do
          expect { subject }.to raise_error(
            ArgumentError,
            "Can't coerce argument '#{arg}'; " \
            'must be either a Class, Module or message matcher (respond to :matches_message?)',
          )
        end
      end
    end
  end
end
