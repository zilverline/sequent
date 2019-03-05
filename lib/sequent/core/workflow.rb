require_relative 'helpers/message_handler'

module Sequent
  module Core
    class Workflow
      include Helpers::MessageHandler

      def execute_commands(*commands)
        Sequent.configuration.command_service.execute_commands(*commands)
      end

      # Workflow#after_commit will accept a block to execute
      # after the transaction commits. This is very useful to
      # isolate side-effects. They will run only on the
      # transaction's success and will not be able to roll it
      # back when there is an exception. Useful if your background
      # jobs processor is not using the same database connection
      # to enqueue jobs.
      def after_commit(&block)
        Sequent.configuration.transaction_provider.after_commit &block
      end
    end
  end
end
