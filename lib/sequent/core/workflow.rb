require_relative 'helpers/message_handler'

module Sequent
  module Core
    class Workflow
      include Helpers::MessageHandler

      def execute_commands(*commands)
        Sequent.configuration.command_service.execute_commands(*commands)
      end
    end
  end
end
