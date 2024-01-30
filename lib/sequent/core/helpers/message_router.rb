# frozen_string_literal: true

require_relative './attr_matchers/attr_matchers'
require_relative './message_matchers/message_matchers'

module Sequent
  module Core
    module Helpers
      class MessageRouter
        attr_reader :routes, :instanceof_routes

        def initialize
          clear_routes
        end

        ##
        # Registers a handler for the given matchers.
        #
        # A matcher must implement #matches_message?(message) and return a truthy value when it matches,
        # or a falsey value otherwise.
        #
        def register_matchers(*matchers, handler)
          matchers.each do |matcher|
            if matcher.is_a?(MessageMatchers::InstanceOf)
              @instanceof_routes[matcher.expected_class] << handler
              @instanceof_routes.each do |expected_class, handlers|
                handlers << handler if expected_class < matcher.expected_class
              end
            else
              @routes[matcher] << handler
            end
          end
        end

        ##
        # Returns a set of handlers that match the given message, or an empty set when none match.
        #
        def match_message(message)
          if !@instanceof_routes.include? message.class
            # Find all instanceof handlers that match this class and add it to our instanceof_routes
            matching_handlers = @instanceof_routes.reduce(Set.new) do |memo, (type, handlers)|
              memo.merge(handlers) if message.class < type
              memo
            end
            @instanceof_routes[message.class] = matching_handlers
          end

          result = Set.new
          result.merge(@instanceof_routes[message.class])

          @routes.each do |matcher, handlers|
            result.merge(handlers) if matcher.matches_message?(message)
          end
          result
        end

        ##
        # Returns true when there is at least one handler for the given message, or false otherwise.
        #
        def matches_message?(message)
          match_message(message).any?
        end

        ##
        # Removes all routes from the router.
        #
        def clear_routes
          @instanceof_routes = Hash.new { |h, k| h[k] = Set.new }
          @routes = Hash.new { |h, k| h[k] = Set.new }
        end
      end
    end
  end
end
