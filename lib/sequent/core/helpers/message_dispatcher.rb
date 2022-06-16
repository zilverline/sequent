# frozen_string_literal: true

module Sequent
  module Core
    module Helpers
      class MessageDispatcher
        def initialize(message_router, context)
          @message_router = message_router
          @context = context
        end

        def dispatch_message(message)
          @message_router
            .match_message(message)
            .each { |handler| @context.instance_exec(message, &handler) }
        end
      end
    end
  end
end
