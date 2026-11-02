# frozen_string_literal: true

require_relative 'attr_matchers/attr_matchers'
require_relative 'message_matchers/message_matchers'

module Sequent
  module Core
    module Helpers
      class MessageRouter
        EMPTY_HANDLERS = Set.new.freeze

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
          fail ArgumentError, 'handler is required' if handler.nil?

          matchers.each do |matcher|
            if matcher.is_a?(MessageMatchers::InstanceOf)
              (@instanceof_routes[matcher.expected_class] ||= Set.new) << handler
            else
              (@routes[matcher] ||= Set.new) << handler
            end
          end
        end

        ##
        # Returns a set of handlers that match the given message, or an empty (frozen) set when none match.
        #
        def match_message(message)
          instanceof_handlers = @instanceof_routes[message.class]
          result = Set.new(instanceof_handlers) if instanceof_handlers
          @routes.each do |matcher, handlers|
            (result ||= Set.new).merge(handlers) if matcher.matches_message?(message)
          end
          result || EMPTY_HANDLERS
        end

        ##
        # Returns true when there is at least one handler for the given message, or false otherwise.
        #
        def matches_message?(message)
          @instanceof_routes.include?(message.class) ||
            @routes.keys.any? { |matcher| matcher.matches_message?(message) }
        end

        ##
        # Removes all routes from the router.
        #
        def clear_routes
          @instanceof_routes = {}
          @routes = {}
        end
      end
    end
  end
end
