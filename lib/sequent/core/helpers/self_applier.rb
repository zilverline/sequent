module Sequent
  module Core
    module Helpers
      ##
      # Creates ability to use DSL like:
      # class MyEventHandler < Sequent::Core::BaseEventHandler
      #
      #   on MyEvent do |event|
      #     do_some_logic
      #   end
      # end
      #
      # You typically do not need to include this module in your classes. If you extend from
      # Sequent::Core::AggregateRoot, Sequent::Core::Projector, Sequent::Core::Workflow or Sequent::Core::BaseCommandHandler
      # you will get this functionality for free.
      #
      module SelfApplier

        module ClassMethods
          def on(*message_classes, &block)
            message_classes.each { |message_class| message_mapping[message_class] = block }
          end

          def message_mapping
            @message_mapping ||= {}
          end

          def handles_message?(message)
            message_mapping.keys.include? message.class
          end
        end

        def self.included(host_class)
          host_class.extend(ClassMethods)
        end

        def handles_message?(message)
          self.class.handles_message?(message)
        end

        def handle_message(message)
          handler = self.class.message_mapping[message.class]
          self.instance_exec(message, &handler) if handler
        end
      end
    end
  end
end
