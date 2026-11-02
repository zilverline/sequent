# frozen_string_literal: true

module Sequent
  module Core
    module Helpers
      #
      # The event handlers in +Sequent.configuration.event_handlers+ are either event handler instances,
      # which handle all events, or event handler classes. An event handler class gets a new instance for
      # every batch of events it handles (see +EventHandlerDispatch+), like a controller is instantiated for
      # every request, so it can safely keep state in instance variables while handling a batch.
      #
      module EventHandlers
        ##
        # The class of the given registered event handler (an event handler class or instance).
        def self.handler_class(event_handler)
          event_handler.is_a?(Class) ? event_handler : event_handler.class
        end

        ##
        # The phase of the given registered event handler. Event handlers without a phase have the
        # +inline+ phase.
        def self.phase(event_handler)
          handler_class = handler_class(event_handler)
          handler_class.respond_to?(:phase) ? handler_class.phase : :inline
        end
      end
    end
  end
end
