# frozen_string_literal: true

require 'active_support'
require 'active_support/core_ext/class/attribute'

require_relative 'message_handler_option_registry'
require_relative 'message_router'

module Sequent
  module Core
    module Helpers
      ##
      # Creates ability to use DSL like:
      #
      #   class MyProjector < Sequent::Projector
      #
      #     on MyEvent do |event|
      #       @foo = event.foo
      #     end
      #
      #   end
      #
      # If you extend from +Sequent::AggregateRoot+, +Sequent::Projector+, +Sequent::Workflow+
      # or +Sequent::CommandHandler+ you will get this functionality
      # for free.
      #
      # It is possible to register multiple handler blocks in the same +MessageHandler+
      #
      #   class MyProjector < Sequent::Projector
      #
      #     on MyEvent do |event|
      #       @foo = event.foo
      #     end
      #
      #     on MyEvent, OtherEvent do |event|
      #       @bar = event.bar
      #     end
      #
      #   end
      #
      # The order of which handler block is executed first is not guaranteed.
      #
      # Hooks can run code before, after or around each invocation of a handler block, for example to
      # add instrumentation. They are only run when a handler block is invoked, and receive the
      # messages the handler block handles (an array containing the single message it handles):
      #
      #   class MyProjector < Sequent::Projector
      #     before_handler { |messages| ... }
      #     after_handler { |messages| ... }
      #
      #     # An around hook continues by calling the handler, or skips the handler block by not
      #     # calling it.
      #     around_handler { |messages, handler| handler.call unless skip?(messages) }
      #
      #     # A hook can also be a method. An around hook method continues by yielding.
      #     around_handler :instrument
      #
      #     def instrument(messages)
      #       Instrumenter.instrument(messages.first.class.name) { yield }
      #     end
      #   end
      #
      # The before hooks run in the order in which they are declared, then the around hooks (the first
      # declared hook is the outermost), the handler block and the after hooks. Like ActiveModel
      # callbacks, the after hooks do not run when an exception propagates from the handler block or the
      # around hooks. An around hook that rescues the exception, or skips the handler block, completes
      # the invocation, so the after hooks do run then. Hooks are inherited by subclasses.
      #
      module MessageHandler
        class UnhandledMessageError < RuntimeError; end

        NO_HOOKS = {before: [].freeze, around: [].freeze, after: [].freeze}.freeze

        module ClassMethods
          def on(*args, **opts, &handler)
            OnArgumentsValidator.validate_arguments!(*args)

            message_matchers = args.map { |arg| MessageMatchers::ArgumentCoercer.coerce_argument(arg) }

            unbound_method = begin
              handler_method_name = :"__sequent_handler_#{handler.object_id}"
              fail "duplicate method name #{handler_method_name}" if method_defined?(handler_method_name)

              define_method(handler_method_name, &handler)
              instance_method(handler_method_name)
            ensure
              undef_method(handler_method_name)
            end

            message_router.register_matchers(
              *message_matchers,
              unbound_method,
            )

            opts.each do |name, value|
              option_registry.call_option(self, name, message_matchers, value)
            end
          end

          ##
          # Registers a hook that runs before each invocation of a handler block. Either a method name
          # or a block, which receive the messages the handler block handles.
          def before_handler(method_name = nil, &block)
            add_handler_hook(:before, method_name, block)
          end

          ##
          # Registers a hook that runs after each successful invocation of a handler block. Either a
          # method name or a block, which receive the messages the handler block handles.
          def after_handler(method_name = nil, &block)
            add_handler_hook(:after, method_name, block)
          end

          ##
          # Registers a hook that runs around each invocation of a handler block. Either a method name,
          # which receives the messages the handler block handles and continues by yielding, or a block,
          # which receives these messages and the handler and continues by calling the handler.
          def around_handler(method_name = nil, &block)
            add_handler_hook(:around, method_name, block)
          end

          def option(name, &block)
            option_registry.register_option(name, block)
          end

          def message_mapping
            message_router.instanceof_routes
          end

          def handles_message?(message)
            message_router.matches_message?(message)
          end

          def message_router
            @message_router ||= MessageRouter.new
          end

          private

          def add_handler_hook(kind, method_name, block)
            if method_name.nil? == block.nil?
              fail ArgumentError, "#{kind}_handler requires either a method name or a block"
            end

            hooks = handler_hooks
            self.handler_hooks = hooks.merge(kind => [*hooks[kind], method_name || block].freeze).freeze
          end
        end

        class OnArgumentsValidator
          class << self
            def validate_arguments!(*args)
              fail ArgumentError, "Must provide at least one argument to 'on'" if args.empty?

              duplicates = args
                .select { |arg| args.count(arg) > 1 }
                .uniq

              if duplicates.any?
                humanized_duplicates = duplicates
                  .map { |x| MessageMatchers::ArgumentSerializer.serialize_value(x) }
                  .join(', ')

                fail ArgumentError,
                     "Arguments to 'on' must be unique, duplicates: #{humanized_duplicates}"
              end
            end
          end
        end

        def self.included(host_class)
          host_class.extend(ClassMethods)
          host_class.extend(MessageMatchers)
          host_class.extend(AttrMatchers)

          host_class.class_attribute :option_registry, default: MessageHandlerOptionRegistry.new
          host_class.class_attribute :handler_hooks, default: NO_HOOKS, instance_accessor: false
        end

        def handle_message(message)
          handlers = self.class.message_router.match_message(message)
          dispatch_message(message, handlers) unless handlers.empty?
        end

        # Like `handle_message` but fails with a `UnhandledMessageError` if
        # there are no handlers matching `message`.
        def handle_message!(message)
          handlers = self.class.message_router.match_message(message)
          fail UnhandledMessageError, "#{self.class}: no handlers defined for #{message.class}" if handlers.empty?

          dispatch_message(message, handlers)
        end

        def dispatch_message(message, handlers)
          hooks = self.class.handler_hooks
          handlers.each do |handler|
            if Sequent.logger.debug?
              Sequent.logger.debug("[MessageHandler] Handler #{self.class} handling #{message.class}")
            end

            args = handler.arity == 0 ? [] : [message]
            if hooks.equal?(NO_HOOKS)
              handler.bind_call(self, *args)
            else
              with_handler_hooks(hooks, [message]) { handler.bind_call(self, *args) }
            end
          end
        end

        private

        def with_handler_hooks(hooks, messages, &handler)
          hooks[:before].each { |hook| call_handler_hook(hook, messages) }
          call_around_handler_hooks(hooks[:around], 0, messages, &handler)
          hooks[:after].each { |hook| call_handler_hook(hook, messages) }
        end

        def call_handler_hook(hook, messages)
          if hook.is_a?(Proc)
            instance_exec(messages, &hook)
          else
            send(hook, messages)
          end
        end

        def call_around_handler_hooks(around_hooks, index, messages, &handler)
          return handler.call if index == around_hooks.size

          # A proc, not a lambda, so it can be passed to code that yields arguments to the block.
          continue = proc { call_around_handler_hooks(around_hooks, index + 1, messages, &handler) }
          hook = around_hooks[index]
          if hook.is_a?(Proc)
            instance_exec(messages, continue, &hook)
          else
            send(hook, messages, &continue)
          end
        end
      end
    end
  end
end
