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
          def on(*message_classes, &block)
            message_classes.each do |message_class|
              message_mapping[message_class.name] ||= []
              message_mapping[message_class.name] << block
            end
          end

          def message_mapping
            @message_mapping ||= {}
          end

          def handles_message?(message)
            message_mapping.keys.include? message.class.name
          end
        end

        def self.included(host_class)
          host_class.extend(ClassMethods)
        end

        def handle_message(message)
          handlers = self.class.message_mapping[message.class.name]
          handlers.each { |handler| self.instance_exec(message, &handler) } if handlers
        end
      end
    end
  end
end
