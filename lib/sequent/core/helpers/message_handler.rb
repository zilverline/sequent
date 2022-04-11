# frozen_string_literal: true

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
        class ConfigurationError < StandardError; end

        module ClassMethods
          def on(*message_classes, &block)
            message_classes.each do |message_class|
              register_message_class(message_class, block)
            end
          end

          def message_mapping
            @message_mapping ||= {}
          end

          def handles_message?(message)
            message_mapping.keys.include? message.class
          end

          def message_base_class(clazz)
            unless clazz.is_a?(ActiveSupport::DescendantsTracker)
              fail ArgumentError,
                   "'message_base_class' should be an ActiveSupport::DescendantsTracker"
            end

            @message_base_class = clazz
          end

          def get_message_base_class
            current = self

            loop do
              message_base_class = current.instance_variable_get(:@message_base_class)
              return message_base_class if message_base_class
              break unless superclass < MessageHandler

              current = superclass
            end

            fail(
              ConfigurationError,
              "Missing message base class configuration for '#{name}', please configure it using `message_base_class`",
            )
          end

          def reset_message_base_class
            @message_base_class = nil
          end

          private

          def register_message_class(message_class, block)
            message_classes_to_register(message_class).each do |clazz|
              message_base_class = get_message_base_class
              unless clazz == message_base_class || clazz < message_base_class
                fail ConfigurationError, "Expected '#{clazz.name}' to be a descendant from '#{message_base_class.name}'"
              end

              message_mapping[clazz] ||= []
              message_mapping[clazz] << block
            end
          end

          def message_classes_to_register(message_class)
            case message_class
            when Class
              [message_class, *message_class.descendants]
            when Module
              get_message_base_class
                .descendants
                .select do |descendant_class|
                  descendant_class.include?(message_class)
                end
            else
              fail ArgumentError, "Required argument 'message_class' should be either a Class or Module"
            end
          end
        end

        def self.included(host_class)
          host_class.extend(ClassMethods)
        end

        def handle_message(message)
          handlers = self.class.message_mapping[message.class]
          handlers&.each { |handler| instance_exec(message, &handler) }
        end
      end
    end
  end
end
