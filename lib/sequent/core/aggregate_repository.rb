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

      class NonUniqueAggregateId < Exception
        def initialize(existing, new)
          super "Duplicate aggregate #{new} with same key as existing #{existing}"
        end
      end

      def initialize(event_store)
        @event_store = event_store
        clear
      end

      # Adds the given aggregate to the repository (or unit of work).
      #
      # Only when +commit+ is called all aggregates in the unit of work are 'processed'
      # and all uncammited_events are stored in the +event_store+
      #
      def add_aggregate(aggregate)
        if aggregates.has_key?(aggregate.id)
          raise NonUniqueAggregateId.new(aggregate, aggregates[aggregate.id]) unless aggregates[aggregate.id].equal?(aggregate)
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
      #
      # If we implement snapshotting this is the place.
      def load_aggregate(aggregate_id, clazz)
        if aggregates.has_key?(aggregate_id)
          result = aggregates[aggregate_id]
          raise TypeError, "#{result.class} is not a #{clazz}" unless result.is_a?(clazz)
          result
        else
          events = @event_store.load_events(aggregate_id)
          aggregates[aggregate_id] = clazz.load_from_history(events)
        end
      end

      # Gets all uncommitted_events from the 'registered' aggregates
      # and stores them in the event store.
      # The command is 'attached' for traceability purpose so we can see
      # which command resulted in which events.
      #
      # This is all abstracted away if you use the Sequent::Core::CommandService
      #
      def commit(command)
        all_events = []
        aggregates.each_value { |aggregate| all_events += aggregate.uncommitted_events }
        return if all_events.empty?
        aggregates.each_value { |aggregate| aggregate.clear_events }
        store_events command, all_events
      end

      # Clears the Unit of Work.
      def clear
        Thread.current[AGGREGATES_KEY] = {}
      end

      private

      def aggregates
        Thread.current[AGGREGATES_KEY]
      end

      def store_events(command, events)
        @event_store.commit_events(command, events)
      end
    end
  end
end
