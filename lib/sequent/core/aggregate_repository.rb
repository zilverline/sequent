module Sequent
  module Core
    # Repository for aggregates.
    #
    # Implements the Unit-Of-Work and Identity-Map patterns
    # to ensure each aggregate is only loaded once per transaction
    # and that you always get the same aggregate instance back.
    #
    # On commit all aggregates associated with the Unit-Of-Work are
    # queried for uncommitted events. After persisting these events
    # the uncommitted events are cleared from the aggregate.
    #
    # The repository is keeps track of the Unit-Of-Work per thread,
    # so can be shared between threads.
    class AggregateRepository
      # Key used in thread local
      AGGREGATES_KEY = 'Sequent::Core::AggregateRepository::aggregates'.to_sym

      attr_reader :event_store

      class NonUniqueAggregateId < StandardError
        def initialize(existing, new)
          super "Duplicate aggregate #{new} with same key as existing #{existing}"
        end
      end

      class AggregateNotFound < StandardError
        def initialize(id)
          super "Aggregate with id #{id} not found"
        end
      end

      def initialize(event_store)
        @event_store = event_store
      end

      # Adds the given aggregate to the repository (or unit of work).
      #
      # Only when +commit+ is called all aggregates in the unit of work are 'processed'
      # and all uncammited_events are stored in the +event_store+
      #
      def add_aggregate(aggregate)
        existing = aggregates[aggregate.id]
        if existing && !existing.equal?(aggregate)
          raise NonUniqueAggregateId.new(aggregate, aggregates[aggregate.id])
        else
          aggregates[aggregate.id] = aggregate
        end
      end

      # Throws exception if not exists.
      def ensure_exists(aggregate_id, clazz)
        !load_aggregate(aggregate_id, clazz).nil?
      end

      # Loads aggregate by given id and class
      # Returns the one in the current Unit Of Work otherwise loads it from history.
      def load_aggregate(aggregate_id, clazz = nil)
        result = aggregates.fetch(aggregate_id) do |_|
          stream, events = @event_store.load_events(aggregate_id)
          raise AggregateNotFound.new(aggregate_id) unless stream
          aggregate_class = Class.const_get(stream.aggregate_type)
          aggregate_class.load_from_history(stream, events)
        end

        raise TypeError, "#{result.class} is not a #{clazz}" if clazz && result && !(result.class <= clazz)
        aggregates[aggregate_id] = result

      end

      ##
      # Returns whether the event store has an aggregate with the given id
      def contains_aggregate?(aggregate_id)
        @event_store.stream_exists?(aggregate_id)
      end

      # Gets all uncommitted_events from the 'registered' aggregates
      # and stores them in the event store.
      # The command is 'attached' for traceability purpose so we can see
      # which command resulted in which events.
      #
      # This is all abstracted away if you use the Sequent::Core::CommandService
      #
      def commit(command)
        updated_aggregates = aggregates.values.reject { |x| x.uncommitted_events.empty? }
        return if updated_aggregates.empty?
        streams_with_events = updated_aggregates.map do |aggregate|
          [ aggregate.event_stream, aggregate.uncommitted_events ]
        end
        updated_aggregates.each(&:clear_events)
        store_events command, streams_with_events
      end

      # Clears the Unit of Work.
      def clear
        Thread.current[AGGREGATES_KEY] = nil
      end

      private

      def aggregates
        Thread.current[AGGREGATES_KEY] ||= {}
      end

      def store_events(command, streams_with_events)
        @event_store.commit_events(command, streams_with_events)
      end
    end
  end
end
