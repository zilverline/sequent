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
      # The order of which handler block is executed first is not guaranteed. So prefer a single handler
      # block per message, instead of multiple handler blocks that depend on each other's results.
      #
      # A handler block can also handle all matching messages at once, for example to insert all
      # records using a single statement:
      #
      #   class MyProjector < Sequent::Projector
      #
      #     on_batch MyEvent do |events|
      #       create_records(MyRecord, events.map { |event| {aggregate_id: event.aggregate_id} })
      #     end
      #
      #   end
      #
      # A batch handler block is called with consecutive matching messages, in the order in which they
      # were published. The messages are always handled in order: a batch is handled as soon as a
      # message is handled by other handler blocks, and for a single message the batch handler blocks
      # are called before the +on+ handler blocks. In the +bulk+ and
      # +before_commit+ phases (see +StagedEventPublisher.with_phases+) the event publisher passes all
      # events of a command (or of a whole transaction) in one batch. In the +inline+ phase, and when a
      # single message is handled using +handle_message+, the batch handler blocks are called with a
      # batch containing only that message.
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

        # A handler block registered using +on_batch+.
        BatchHandler = Struct.new(:unbound_method)

        NO_HOOKS = {before: [].freeze, around: [].freeze, after: [].freeze}.freeze

        @handler_hooks_version = 0

        class << self
          # Incremented whenever a hook is added, so the classes recombine their inherited hooks.
          attr_reader :handler_hooks_version

          def handler_hooks_changed!
            @handler_hooks_version += 1
          end
        end

        module ClassMethods
          def on(*args, **opts, &handler)
            register_handler(args, opts, handler) { |unbound_method| unbound_method }
          end

          ##
          # Registers a handler block that is called with all matching messages at once. See
          # +MessageHandler+.
          def on_batch(*args, **opts, &handler)
            register_handler(args, opts, handler) { |unbound_method| BatchHandler.new(unbound_method) }
            @batch_handlers = true
          end

          ##
          # Whether any handler blocks are registered using +on_batch+.
          def batch_handlers?
            @batch_handlers == true
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

          ##
          # The hooks of this class, including the hooks inherited from its superclasses, also when these
          # are added after this class added its own hooks.
          def handler_hooks
            version = MessageHandler.handler_hooks_version
            return @handler_hooks if @handler_hooks_version == version

            @handler_hooks = combine_handler_hooks
            @handler_hooks_version = version
            @handler_hooks
          end

          private

          def add_handler_hook(kind, method_name, block)
            if method_name.nil? == block.nil?
              fail ArgumentError, "#{kind}_handler requires either a method name or a block"
            end

            own_hooks = @own_handler_hooks || NO_HOOKS
            @own_handler_hooks = own_hooks.merge(kind => [*own_hooks[kind], method_name || block].freeze).freeze
            MessageHandler.handler_hooks_changed!
          end

          # The hooks of the superclass followed by the hooks of this class, or +NO_HOOKS+ when there are
          # none at all.
          def combine_handler_hooks
            inherited = superclass.respond_to?(:handler_hooks) ? superclass.handler_hooks : NO_HOOKS
            return inherited if @own_handler_hooks.nil?
            return @own_handler_hooks if inherited.equal?(NO_HOOKS)

            inherited.to_h { |kind, hooks| [kind, (hooks + @own_handler_hooks[kind]).freeze] }.freeze
          end

          def register_handler(args, opts, handler)
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
              yield(unbound_method),
            )

            opts.each do |name, value|
              option_registry.call_option(self, name, message_matchers, value)
            end
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
        end

        ##
        # Handles the +message+, see +handle_messages+.
        #
        # @return the number of handler blocks invoked.
        def handle_message(message, on_error: nil)
          # A class without batch handler blocks handles a single message without a batch.
          return handle_messages([message], on_error:) if self.class.batch_handlers?

          invoke_handlers(message, match_handlers(message), on_error)
        end

        ##
        # Handles all +messages+ in order. Consecutive messages that are only handled by the same batch
        # handler blocks (registered using +on_batch+) are passed to these blocks in a single batch.
        #
        # @param on_error called with the messages and the error when a handler block (or one of its
        #   hooks) fails to handle these messages, for example to raise an error that tells which
        #   message failed. The error is raised as is when +on_error+ returns, or when it is +nil+.
        # @return the number of handler blocks invoked, where a batch handler block invoked with a batch
        #   of messages counts once.
        def handle_messages(messages, on_error: nil)
          unless self.class.batch_handlers?
            return messages.sum { |message| invoke_handlers(message, match_handlers(message), on_error) }
          end

          count = 0
          batch = []
          batch_handlers = Set.new

          messages.each do |message|
            handlers = match_handlers(message)
            message_batch_handlers = handlers.grep(BatchHandler).to_set
            individual_handlers = handlers.grep_v(BatchHandler)

            if message_batch_handlers != batch_handlers
              count += invoke_batch_handlers(batch, batch_handlers, on_error)
              batch = []
              batch_handlers = message_batch_handlers
            end
            batch << message unless batch_handlers.empty?
            next if individual_handlers.empty?

            # The batch is handled first, so the messages are handled in order.
            count += invoke_batch_handlers(batch, batch_handlers, on_error)
            batch = []
            count += invoke_handlers(message, individual_handlers, on_error)
          end

          count + invoke_batch_handlers(batch, batch_handlers, on_error)
        end

        # Like `handle_message` but fails with a `UnhandledMessageError` if
        # there are no handlers matching `message`.
        def handle_message!(message)
          count = handle_message(message)
          fail UnhandledMessageError, "#{self.class}: no handlers defined for #{message.class}" if count.zero?

          count
        end

        private

        def match_handlers(message)
          self.class.message_router.match_message(message)
        end

        def invoke_handlers(message, handlers, on_error)
          hooks = self.class.handler_hooks
          handlers.each do |handler|
            if Sequent.logger.debug?
              Sequent.logger.debug("[MessageHandler] Handler #{self.class} handling #{message.class}")
            end

            args = handler.arity == 0 ? [] : [message]
            if hooks.equal?(NO_HOOKS) && on_error.nil?
              handler.bind_call(self, *args)
            else
              invoke_handler(hooks, [message], on_error) { handler.bind_call(self, *args) }
            end
          end
          handlers.size
        end

        def invoke_batch_handlers(messages, batch_handlers, on_error)
          return 0 if messages.empty?

          hooks = self.class.handler_hooks
          batch_handlers.each do |batch_handler|
            if Sequent.logger.debug?
              Sequent.logger.debug(
                "[MessageHandler] Handler #{self.class} handling a batch of #{messages.size} messages",
              )
            end

            invoke_handler(hooks, messages, on_error) { batch_handler.unbound_method.bind_call(self, messages) }
          end
          batch_handlers.size
        end

        def invoke_handler(hooks, messages, on_error, &handler)
          if hooks.equal?(NO_HOOKS)
            yield
          else
            with_handler_hooks(hooks, messages, &handler)
          end
        rescue StandardError => e
          on_error&.call(messages, e)
          raise
        end

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
