# frozen_string_literal: true

require_relative './message_matchers/message_matchers'

module Sequent
  module Core
    module Helpers
      class MessageRouter
        attr_reader :routes

        def initialize
          @routes = Hash.new { |h, k| h[k] = Set.new }
        end

        ##
        # Registers a handler for the given matchers.
        #
        # A matcher must implement #matches_message?(message) and return a truthy value when it matches,
        # or a falsey value otherwise.
        #
        def register_matchers(*matchers, handler)
          matchers.each do |matcher|
            @routes[matcher] << handler
          end
        end

        ##
        # Returns a set of handlers that match the given message, or an empty set when none match.
        #
        def match_message(message)
          @routes
            .reduce(Set.new) do |memo, (matcher, handlers)|
              memo = memo.merge(handlers) if matcher.matches_message?(message)
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
