# frozen_string_literal: true

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
      module MessageHandler
        module ClassMethods
          def on(*args, **opts, &block)
            OnArgumentsValidator.validate_arguments!(*args)

            message_matchers = args.map { |arg| MessageMatchers::ArgumentCoercer.coerce_argument(arg) }

            message_router.register_matchers(
              *message_matchers,
              block,
            )

            opts.each do |name, value|
              option_registry.call_option(self, name, message_matchers, value)
            end
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

        def handle_message(message)
          handlers = self.class.message_router.match_message(message)
          dispatch_message(message, handlers) unless handlers.empty?
        end

        def dispatch_message(message, handlers)
          handlers.each do |handler|
            if Sequent.logger.debug?
              Sequent.logger.debug("[MessageHandler] Handler #{self.class} handling #{message.class}")
            end
            instance_exec(message, &handler)
          end
        end
      end
    end
  end
end
