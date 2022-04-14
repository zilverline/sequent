# frozen_string_literal: true

require_relative 'message_router'
require_relative 'message_dispatcher'

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
          def on(*args, &block)
            OnArgumentsValidator.validate_arguments!(*args)

            message_router.register_matchers(
              *args.map { |arg| OnArgumentCoercer.coerce_argment(arg) },
              block,
            )
          end

          def message_mapping
            message_router
              .routes
              .map { |k, v| [k.expected_class, v] }
              .to_h
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
                fail ArgumentError,
                     "Arguments to 'on' must be unique, duplicates: #{duplicates.join(', ')}"
              end
            end
          end
        end

        class OnArgumentCoercer
          class << self
            def coerce_argment(arg)
              fail ArgumentError, "Argument to 'on' cannot be nil" if arg.nil?

              return MessageMatchers::ClassEquals.new(expected_class: arg) if [Class, Module].include?(arg.class)
              return arg if arg.respond_to?(:matches_message?)

              fail ArgumentError,
                   "Can't coerce argument '#{arg}'; " \
                   'must be either a Class, Module or message matcher (respond to :matches_message?)'
            end
          end
        end

        def self.included(host_class)
          host_class.extend(ClassMethods)
        end

        def handle_message(message)
          message_dispatcher.dispatch_message(message)
        end

        private

        def message_dispatcher
          MessageDispatcher.new(self.class.message_router, self)
        end
      end
    end
  end
end
