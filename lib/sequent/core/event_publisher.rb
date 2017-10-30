module Sequent
  module Core
    class EventPublisher
      class PublishEventError < RuntimeError
        attr_reader :event_handler_class, :event

        def initialize(event_handler_class, event)
          @event_handler_class = event_handler_class
          @event = event
        end

        def message
          "Event Handler: #{@event_handler_class.inspect}\nEvent: #{@event.inspect}\nCause: #{cause.inspect}"
        end
      end

      def initialize
        @events_queue = Queue.new
        @mutex = Mutex.new
      end

      def publish_events(events)
        return if configuration.disable_event_handlers
        events.each { |event| @events_queue.push(event) }
        process_events
      end

      private

      def process_events
        # only process events at the highest level
        return if @mutex.locked?

        @mutex.synchronize do
          while(!@events_queue.empty?) do
            event = @events_queue.pop
            configuration.event_handlers.each do |handler|
              begin
                handler.handle_message event
              rescue
                raise PublishEventError.new(handler.class, event)
              end
            end
          end
        end
      end

      def configuration
        Sequent.configuration
      end
    end
  end
end
