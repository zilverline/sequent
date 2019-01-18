require_relative 'helpers/message_handler'

module Sequent
  module Core
    class Workflow
      include Helpers::MessageHandler

      def self.on(*message_classes, &block)
        decorated_block = ->(event) do
          begin
            old_event = Thread.current[:handling_event]
            Thread.current[:handling_event] = event
            self.instance_exec(event, &block)
          ensure
            Thread.current[:handling_event] = old_event
          end
        end
        super(*message_classes, &decorated_block)
      end

      def current_event
        Thread.current[:handling_event]
      end

      def execute_commands(*commands)
        commands.each do |command|
          if command.respond_to?(:event_aggregate_id) && command.event_aggregate_id.blank?
            command.event_aggregate_id = current_event.aggregate_id
            command.event_sequence_number = current_event.sequence_number
          end
        end

        Sequent.configuration.command_service.execute_commands(*commands)
      end

      # Workflow#after_commit will accept a block to execute
      # after the transaction commits. This is very useful to
      # isolate side-effects. They will run only on the
      # transaction's success and will not be able to roll it
      # back when there is an exception. Useful if your background
      # jobs processor is not using the same database connection
      # to enqueue jobs.
      def after_commit(ignore_errors: false, &block)
        Sequent.configuration.transaction_provider.after_commit &block
      rescue StandardError => error
        if ignore_errors
          Sequent.logger.warn("An exception was raised in an after_commit hook: #{error}, #{error.inspect}")
        else
          raise error
        end
      end
    end
  end
end
