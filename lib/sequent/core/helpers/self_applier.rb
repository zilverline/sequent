module Sequent
  module Core
    module Helpers
      module SelfApplier

        ##
        # Creates ability to use DSL like:
        # class MyEventHandler
        #   include Sequent::Core::Helpers::SelfApplier
        #
        #   on MyEvent do |event|
        #     do_some_logic
        #   end
        # end
        module ClassMethods

          def on(*message_classes, &block)
            @message_mapping ||= {}
            message_classes.each { |message_class| @message_mapping[message_class] = block }
          end

          def message_mapping
            @message_mapping || {}
          end
        end

        def self.included(host_class)
          host_class.extend(ClassMethods)
        end

        def handle_message(message)
          handler = self.class.message_mapping[message.class]
          self.instance_exec(message, &handler) if handler
        end

      end

    end
  end
end

