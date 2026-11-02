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

  context 'with batch handlers' do
    class MyBatchHandler
      include Sequent::Core::Helpers::MessageHandler

      attr_reader :log

      def initialize
        @log = []
      end

      on_batch MessageHandlerEvent do |events|
        @log << [:batch, events.size]
      end

      on MessageHandlerEvent, MessageHandlerEventOtherEvent do |event|
        @log << [:individual, event.class]
      end
    end

    let(:handler) { MyBatchHandler.new }
    let(:event) { MessageHandlerEvent.new }
    let(:other_event) { MessageHandlerEventOtherEvent.new(aggregate_id: '2', sequence_number: 1) }

    it 'handles the batch handlers like other handlers' do
      expect(MyBatchHandler.batch_handlers?).to be_truthy
      expect(MyHandler.batch_handlers?).to be_falsey
      expect(MyBatchHandler.handles_message?(event)).to be_truthy
      expect(MyBatchHandler.message_mapping.keys).to contain_exactly(MessageHandlerEvent, MessageHandlerEventOtherEvent)
    end

    it 'calls the batch handlers with a batch of one message when handling a single message' do
      handler.handle_message(event)

      expect(handler.log).to eq [[:batch, 1], [:individual, MessageHandlerEvent]]
    end

    it 'handles the messages in order, calling the batch handlers before the other handlers of a message' do
      handler.handle_messages([event, other_event, event])

      expect(handler.log).to eq [
        [:batch, 1],
        [:individual, MessageHandlerEvent],
        [:individual, MessageHandlerEventOtherEvent],
        [:batch, 1],
        [:individual, MessageHandlerEvent],
      ]
    end

    context 'with consecutive messages for the same batch handlers' do
      class MyOrderedBatchHandler
        include Sequent::Core::Helpers::MessageHandler

        attr_reader :log

        def initialize
          @log = []
        end

        on_batch MessageHandlerEvent do |events|
          @log << [:batch, events.size]
        end

        on_batch MessageHandlerEvent, MessageHandlerEventOtherEvent do |events|
          @log << [:other_batch, events.size]
        end

        on BaseMessageHandlerEvent do |_event|
          @log << [:individual]
        end
      end

      let(:handler) { MyOrderedBatchHandler.new }
      let(:base_event) { BaseMessageHandlerEvent.new }

      it 'handles these messages in a single batch until a message is handled by other handlers' do
        handler.handle_messages([event, event, other_event, other_event, base_event, event])

        expect(handler.log).to eq [
          [:batch, 2],
          [:other_batch, 2],
          [:other_batch, 2],
          [:individual],
          [:batch, 1],
          [:other_batch, 1],
        ]
      end
    end
  end

  context 'return value' do
    it 'returns the number of handler blocks invoked' do
      expect(MyHandler.new.handle_message(MessageHandlerEvent.new)).to eq 2
      expect(MyHandler.new.handle_message(BaseMessageHandlerEvent.new)).to eq 0
      expect(MyHandler.new.handle_messages([MessageHandlerEvent.new, MessageHandlerEvent.new])).to eq 4
      expect(MyHandler.new.handle_message!(MessageHandlerEvent.new)).to eq 2
    end

    it 'counts a batch handler invoked with a batch of messages once' do
      event = MessageHandlerEvent.new
      other_event = MessageHandlerEventOtherEvent.new(aggregate_id: '2', sequence_number: 1)

      expect(MyOrderedBatchHandler.new.handle_messages([event, event, other_event])).to eq 3
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

      on_batch MessageHandlerEventOtherEvent do |events|
        @log << [:batch_handler, events.size]
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
    let(:other_event) { MessageHandlerEventOtherEvent.new(aggregate_id: '2', sequence_number: 1) }

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

    it 'passes the batch of messages to the hooks of a batch handler block' do
      handler.handle_messages([other_event, other_event])

      expect(handler.log.first).to eq [:before, 2]
      expect(handler.log).to include [:batch_handler, 2]
    end

    it 'does not run the hooks when no handler block is invoked' do
      handler.handle_message(BaseMessageHandlerEvent.new)

      expect(handler.log).to be_empty
    end

    it 'inherits the hooks, and skips the handler block when an around hook does not continue' do
      skipping_handler = SkippingHookedHandler.new
      skipping_handler.skip = true

      expect(skipping_handler.handle_message(MessageHandlerEvent.new)).to eq 1
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

    it 'invokes the handler blocks of a class without hooks directly' do
      plain_handler = MyHandler.new
      expect(plain_handler).not_to receive(:with_handler_hooks)

      plain_handler.handle_message(MessageHandlerEvent.new)

      expect(plain_handler.first_block_called).to be_truthy
    end

    it 'does not run the after hooks when the handler block fails' do
      failing_handler = Class.new(HookedHandler) do
        on MessageHandlerEvent do |_event|
          fail 'handler failed'
        end
      end.new

      expect { failing_handler.handle_message(MessageHandlerEvent.new) }.to raise_error 'handler failed'

      expect(failing_handler.log).not_to include([:after, 1])
    end

    it 'runs the after hooks when an around hook rescues the failure of the handler block' do
      rescuing_handler = Class.new(HookedHandler) do
        around_handler do |_messages, handler|
          handler.call
        rescue StandardError
          @log << :rescued
        end

        on MessageHandlerEvent do |_event|
          fail 'handler failed'
        end
      end.new

      rescuing_handler.handle_message(MessageHandlerEvent.new)

      expect(rescuing_handler.log.last(2)).to eq [:around_method_end, [:after, 1]]
      expect(rescuing_handler.log).to include(:rescued)
    end

    it 'allows passing the handler to code that yields arguments' do
      yielding_handler = Class.new(HookedHandler) do
        around_handler { |_messages, handler| yield_payload(&handler) }
        around_handler :yield_payload

        on MessageHandlerEvent do |_event|
          @log << :handler
        end

        def yield_payload(*)
          yield :payload
        end
      end.new

      yielding_handler.handle_message(MessageHandlerEvent.new)

      expect(yielding_handler.log).to include(:handler)
    end

    it 'runs the hooks added to a superclass after a subclass added its own hooks' do
      parent = Class.new do
        include Sequent::Core::Helpers::MessageHandler

        attr_reader :log

        def initialize
          @log = []
        end
      end
      child = Class.new(parent) do
        before_handler { |_messages| @log << :child }

        on MessageHandlerEvent do |_event|
          @log << :handler
        end
      end
      parent.before_handler { |_messages| @log << :parent }

      handler = child.new
      handler.handle_message(MessageHandlerEvent.new)

      expect(handler.log).to eq %i[parent child handler]
      expect(Class.new(MyHandler).handler_hooks).to be Sequent::Core::Helpers::MessageHandler::NO_HOOKS
    end

    it 'requires either a method name or a block' do
      expect { Class.new(HookedHandler) { before_handler } }.to raise_error ArgumentError
      expect { Class.new(HookedHandler) { before_handler(:foo) { nil } } }.to raise_error ArgumentError
    end
  end

  context 'on_error' do
    class FailingHandlerEvent < Sequent::Event; end

    class FailingHandler
      include Sequent::Core::Helpers::MessageHandler

      on FailingHandlerEvent do |event|
        fail 'event failed' if event.sequence_number == 2
      end

      on_batch MessageHandlerEventOtherEvent do |_events|
        fail 'batch failed'
      end
    end

    let(:handler) { FailingHandler.new }
    let(:events) { [1, 2, 3].map { |n| FailingHandlerEvent.new(aggregate_id: '1', sequence_number: n) } }
    let(:other_events) { [1, 2].map { |n| MessageHandlerEventOtherEvent.new(aggregate_id: '2', sequence_number: n) } }

    it 'is called with the message that failed, and raises the error when it returns' do
      failed = []

      expect do
        handler.handle_messages(events, on_error: ->(messages, error) { failed << [messages, error.message] })
      end.to raise_error 'event failed'

      expect(failed).to eq [[[events[1]], 'event failed']]
    end

    it 'is called with the batch of messages that failed' do
      failed = []

      expect do
        handler.handle_messages(other_events, on_error: ->(messages, _error) { failed << messages })
      end.to raise_error 'batch failed'

      expect(failed).to eq [other_events]
    end

    it 'can raise another error, caused by the error of the handler' do
      on_error = ->(messages, _error) { fail "#{messages.first.sequence_number} failed" }

      expect do
        handler.handle_messages(events, on_error:)
      end.to raise_error(RuntimeError, '2 failed') { |error| expect(error.cause.message).to eq 'event failed' }
    end
  end
end
