# frozen_string_literal: true

module Sequent
  module Core
    module Helpers
      class MessageHandlerOptionRegistry
        attr_reader :entries

        def initialize
          clear_options
        end

        ##
        # Registers a handler for the given option.
        #
        def register_option(name, handler)
          fail ArgumentError, "Option with name '#{name}' already registered" if option_registered?(name)

          @entries[name] = handler
        end

        ##
        # Calls the options with the given arguments with `self` bound to the given context.
        #
        def call_option(context, name, *args)
          handler = find_option(name)
          context.instance_exec(*args, &handler)
        end

        ##
        # Removes all options from the registry.
        #
        def clear_options
          @entries = {}
        end

        private

        ##
        # Returns the handler for given option.
        #
        def find_option(name)
          @entries[name] || fail(
            ArgumentError,
            "Unsupported option: '#{name}'; " \
            "#{@entries.keys.any? ? "registered options: #{@entries.keys.join(', ')}" : 'no registered options'}",
          )
        end

        ##
        # Returns true when an option for the given name is registered, or false otherwise.
        #
        def option_registered?(name)
          @entries.key?(name)
        end
      end
    end
  end
end
