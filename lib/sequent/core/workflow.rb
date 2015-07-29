require_relative 'helpers/self_applier'

module Sequent
  module Core
    class Workflow
      include Helpers::SelfApplier

      def execute_commands(*commands)
        Sequent.configuration.command_service.execute_commands(*commands)
      end
    end
  end
end
