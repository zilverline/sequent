# frozen_string_literal: true

module Sequent
  module Core
    module Helpers
      class MessageRouter
        NO_MATCH = -> { Set.new }

        attr_reader :routes

        def initialize
          @routes = Hash.new { |h, k| h[k] = NO_MATCH.call }
        end

        ##
        # Registers the given handler for the given message classes.
        #
        def register_messages(*message_classes, handler)
          message_classes.each do |message_class|
            @routes[message_class] << handler
          end
        end

        ##
        # Returns a set of handlers that match the given message, or an empty set when none match.
        #
        def match_message(message)
          @routes
            .reduce(NO_MATCH.call) do |memo, (message_class, handlers)|
              memo = memo.merge(handlers) if message.is_a?(message_class)
              memo
            end
        end

        ##
        # Returns true when there is at least one handler for the given message, or false otherwise.
        #
        def matches_message?(message)
          match_message(message).any?
        end
      end
    end
  end
end
