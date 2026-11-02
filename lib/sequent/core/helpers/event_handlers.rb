# frozen_string_literal: true

module Sequent
  module Core
    module Helpers
      #
      # The event handlers in +Sequent.configuration.event_handlers+ are event handler instances or classes,
      # depending on their +lifetime+. An event handler class (with the +batch+ lifetime) gets a new instance
      # for every batch of events it handles (see +EventHandlerDispatch+), like a controller is instantiated
      # for every request, so it can safely keep state in instance variables while handling a batch.
      #
      module EventHandlers
        ##
        # The class of the given registered event handler (an event handler class or instance).
        def self.handler_class(event_handler)
          event_handler.is_a?(Class) ? event_handler : event_handler.class
        end

        LIFETIMES = %i[singleton batch].freeze

        ##
        # The lifetime of the given event handler class: its +lifetime+, or +:batch+ for an event handler in
        # the +bulk+ phase and +:singleton+ otherwise.
        def self.lifetime(handler_class)
          lifetime = handler_class.lifetime if handler_class.respond_to?(:lifetime)
          lifetime ||= phase(handler_class) == :bulk ? :batch : :singleton
          unless LIFETIMES.include?(lifetime)
            fail ArgumentError,
                 "lifetime #{lifetime.inspect} of #{handler_class} is not one of #{LIFETIMES.map(&:inspect).join(', ')}"
          end

          lifetime
        end

        ##
        # The event handler to register for the given event handler class: the class itself when it has the
        # +batch+ lifetime, otherwise an instance.
        def self.registration(handler_class)
          lifetime(handler_class) == :batch ? handler_class : handler_class.new
        end

        ##
        # Fails when an event handler is registered in a way that does not match its lifetime.
        def self.ensure_valid!(event_handlers)
          event_handlers.each do |event_handler|
            handler_class = handler_class(event_handler)
            lifetime = lifetime(handler_class)
            if event_handler.is_a?(Class)
              next if lifetime == :batch

              fail ArgumentError,
                   "#{handler_class} is registered as a class, so it must have the batch lifetime " \
                   '(self.lifetime = :batch), or register an instance instead'
            elsif lifetime == :batch
              fail ArgumentError,
                   "#{handler_class} has the batch lifetime, so register the class instead of an instance"
            end
          end
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
