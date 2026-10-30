# frozen_string_literal: true

module Sequent
  module Core
    module Helpers
      #
      # The event handlers in +Sequent.configuration.event_handlers+ are event handler instances or classes, depending
      # on the +lifetime+ of the event handler class:
      #
      # - +:singleton+ (the default): an instance is registered, which handles all events.
      # - +:batch+: the class is registered, and the +EventPublisher+ creates a new instance for every batch of events
      #   it handles, like a controller is created for every request. The instance can keep state while handling the
      #   batch, like the changes buffered by a +BufferedPersistor+, which the +EventPublisher+ flushes.
      #
      module EventHandlers
        LIFETIMES = %i[singleton batch].freeze

        ##
        # The class of the given registered event handler (an event handler class or instance).
        def self.handler_class(event_handler)
          event_handler.is_a?(Class) ? event_handler : event_handler.class
        end

        ##
        # The lifetime of the given event handler class. Event handlers without a lifetime are singletons.
        def self.lifetime(handler_class)
          lifetime = handler_class.respond_to?(:lifetime) ? handler_class.lifetime : :singleton
          unless LIFETIMES.include?(lifetime)
            fail ArgumentError,
                 "lifetime #{lifetime.inspect} of #{handler_class} is not one of #{LIFETIMES.map(&:inspect).join(', ')}"
          end

          lifetime
        end

        ##
        # The event handler to register for the given event handler class: the class itself when it has the +batch+
        # lifetime, otherwise an instance.
        def self.registration(handler_class)
          lifetime(handler_class) == :batch ? handler_class : handler_class.new
        end

        ##
        # Fails when an event handler is registered in a way that does not match its lifetime, or when a registered
        # projector instance uses a +BufferedPersistor+, which only the +EventPublisher+ flushes.
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
            elsif event_handler.is_a?(Projector) && event_handler.persistor.is_a?(Persistors::BufferedPersistor)
              fail ArgumentError,
                   "#{handler_class} uses a BufferedPersistor, which is only flushed for projectors with the batch " \
                   'lifetime (self.lifetime = :batch)'
            end
          end
        end
      end
    end
  end
end
