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

  context '#handles_message' do
    it 'executes all defined blocks' do
      handler.handle_message(MessageHandlerEvent.new)

      expect(handler.first_block_called).to be_truthy
      expect(handler.last_block_called).to be_truthy
    end

    it 'silently ignores any unknown message' do
      handler.handle_message(BaseMessageHandlerEvent.new)

      expect(handler.first_block_called).to be_falsey
      expect(handler.last_block_called).to be_falsey
    end
  end

  context '#handles_message!' do
    it 'executes all defined blocks' do
      handler.handle_message!(MessageHandlerEvent.new)

      expect(handler.first_block_called).to be_truthy
      expect(handler.last_block_called).to be_truthy
    end

    it 'fails on unknown messages' do
      expect do
        handler.handle_message!(BaseMessageHandlerEvent.new)
      end.to raise_error(Sequent::Core::Helpers::MessageHandler::UnhandledMessageError)
    end
  end

  describe 'options' do
    class HandlerWithOption
      include Sequent::Core::Helpers::MessageHandler

      class_attribute :called_options, default: []
    end

    before do
      HandlerWithOption.message_router.clear_routes
      HandlerWithOption.option_registry.clear_options
    end

    it 'calls registered options' do
      expect do
        HandlerWithOption.option :my_option do |matcher, argument|
          called_options.push([:my_option, matcher, argument])
        end

        HandlerWithOption.on MessageHandlerEvent, my_option: :my_value do
          # ...
        end
      end
        .to change { HandlerWithOption.called_options }
        .from([])
        .to(
          [
            [
              :my_option,
              [Sequent::Core::Helpers::MessageMatchers::InstanceOf.new(MessageHandlerEvent)],
              :my_value,
            ],
          ],
        )
    end

    context 'given no option with the given name is registered' do
      it 'fails' do
        expect do
          HandlerWithOption.on MessageHandlerEvent, my_option: :my_value do
            # ...
          end
        end.to raise_error(ArgumentError, "Unsupported option: 'my_option'; no registered options")
      end
    end

    describe 'option isolation' do
      class SubclassHandlerWithOption < HandlerWithOption
      end

      class UnrelatedHandlerWithOption
        include Sequent::Core::Helpers::MessageHandler

        class_attribute :called_options, default: []
      end

      before do
        SubclassHandlerWithOption.message_router.clear_routes
        SubclassHandlerWithOption.option_registry.clear_options
        UnrelatedHandlerWithOption.message_router.clear_routes
        UnrelatedHandlerWithOption.option_registry.clear_options
      end

      before do
        HandlerWithOption.option :my_option do |matcher, argument|
          called_options.push([:my_option, matcher, argument])
        end

        HandlerWithOption.on MessageHandlerEvent, my_option: :my_value do
          # ...
        end
      end

      context 'given a registered option in a super class' do
        context 'and registering an option with the same name in a sub class' do
          it 'fails' do
            expect do
              SubclassHandlerWithOption.option :my_option do |matcher, argument|
                called_options.push([:my_option, matcher, argument])
              end

              SubclassHandlerWithOption.on MessageHandlerEvent, my_option: :my_value do
                # ...
              end
            end.to raise_error(ArgumentError, "Option with name 'my_option' already registered")
          end
        end

        context 'and registering an option with the same name in an unrelated class' do
          it 'calls registered options' do
            expect do
              UnrelatedHandlerWithOption.option :my_option do |matcher, argument|
                called_options.push([:my_option, matcher, argument])
              end

              UnrelatedHandlerWithOption.on MessageHandlerEvent, my_option: :my_value do
                # ...
              end
            end
              .to change { UnrelatedHandlerWithOption.called_options }
              .from([])
              .to(
                [
                  [
                    :my_option,
                    [Sequent::Core::Helpers::MessageMatchers::InstanceOf.new(MessageHandlerEvent)],
                    :my_value,
                  ],
                ],
              )
          end
        end
      end
    end
  end

  describe '.message_mapping' do
    subject { MyHandler.message_mapping }

    it 'returns a mapping of message classes to unbound methods' do
      expect(subject.keys).to eq(
        [
          MessageHandlerEvent,
          MessageHandlerEventOtherEvent,
        ],
      )
      expect(subject[MessageHandlerEvent].size).to eq(2)
      expect(subject[MessageHandlerEventOtherEvent].size).to eq(1)
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

  describe 'handlers that use `return`' do
    class HandlerWithReturn
      include Sequent::Core::Helpers::MessageHandler

      attr_reader :first_block_called, :second_block_called, :last_block_called

      on MessageHandlerEvent do
        @first_block_called = true
        return
      end

      on MessageHandlerEvent do |_event|
        @second_block_called = true
        next
      end

      on MessageHandlerEvent do
        @last_block_called = true
      end
    end

    let(:handler) { HandlerWithReturn.new }

    it 'should call subsequent handlers when a handler uses `return` or `next`' do
      handler.handle_message(MessageHandlerEvent.new)

      expect(handler.first_block_called).to be_truthy
      expect(handler.second_block_called).to be_truthy
      expect(handler.last_block_called).to be_truthy
    end
  end

  context 'hooks' do
    class HookedHandler
      include Sequent::Core::Helpers::MessageHandler

      attr_reader :log

      def initialize
        @log = []
      end

      before_handler { |messages| @log << [:before, messages.size] }
      around_handler :around_method
      around_handler do |messages, handler|
        @log << [:around_block_start, messages.size]
        handler.call
        @log << :around_block_end
      end
      after_handler { |messages| @log << [:after, messages.size] }

      on MessageHandlerEvent do |_event|
        @log << :handler
      end

      private

      def around_method(messages)
        @log << [:around_method_start, messages.size]
        yield
        @log << :around_method_end
      end
    end

    # Inherits the hooks, but not the handler blocks.
    class SkippingHookedHandler < HookedHandler
      around_handler { |_messages, handler| handler.call unless @skip }

      attr_writer :skip

      on MessageHandlerEvent do |_event|
        @log << :handler
      end
    end

    let(:handler) { HookedHandler.new }

    it 'runs the hooks around each invocation of a handler block, in order' do
      handler.handle_message(MessageHandlerEvent.new)

      expect(handler.log).to eq [
        [:before, 1],
        [:around_method_start, 1],
        [:around_block_start, 1],
        :handler,
        :around_block_end,
        :around_method_end,
        [:after, 1],
      ]
    end

    it 'does not run the hooks when no handler block is invoked' do
      handler.handle_message(BaseMessageHandlerEvent.new)

      expect(handler.log).to be_empty
    end

    it 'runs the hooks when a subclass overrides dispatch_message' do
      overriding_handler = Class.new(HookedHandler) do
        on MessageHandlerEvent do |_event|
          @log << :handler
        end

        def dispatch_message(message, handlers)
          @log << :dispatch
          super
        end
      end.new

      overriding_handler.handle_message(MessageHandlerEvent.new)

      expect(overriding_handler.log.first(2)).to eq [:dispatch, [:before, 1]]
      expect(overriding_handler.log).to include :handler
    end

    it 'inherits the hooks, and skips the handler block when an around hook does not continue' do
      skipping_handler = SkippingHookedHandler.new
      skipping_handler.skip = true

      skipping_handler.handle_message(MessageHandlerEvent.new)

      expect(skipping_handler.log).to eq [
        [:before, 1],
        [:around_method_start, 1],
        [:around_block_start, 1],
        :around_block_end,
        :around_method_end,
        [:after, 1],
      ]
      expect(HookedHandler.handler_hooks[:around].size).to eq 2
    end

    it 'requires either a method name or a block' do
      expect { Class.new(HookedHandler) { before_handler } }.to raise_error ArgumentError
      expect { Class.new(HookedHandler) { before_handler(:foo) { nil } } }.to raise_error ArgumentError
    end
  end
end
