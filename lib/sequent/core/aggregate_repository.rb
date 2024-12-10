# frozen_string_literal: true

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
    # The repository keeps track of the Unit-Of-Work per thread,
    # so can be shared between threads.
    class AggregateRepository
      # Key used in thread local
      AGGREGATES_KEY = 'Sequent::Core::AggregateRepository::aggregates'.to_sym

      class NonUniqueAggregateId < StandardError
        def initialize(existing, new)
          super("Duplicate aggregate #{new} with same key as existing #{existing}")
        end
      end

      class AggregateNotFound < StandardError
        def initialize(id)
          super("Aggregate with id #{id} not found")
        end
      end

      class HasUncommittedEvents < StandardError; end

      # Adds the given aggregate to the repository (or unit of work).
      #
      # Only when +commit+ is called all aggregates in the unit of work are 'processed'
      # and all uncammited_events are stored in the +event_store+
      #
      def add_aggregate(aggregate)
        existing = aggregates[aggregate.id]
        if existing && !existing.equal?(aggregate)
          fail NonUniqueAggregateId.new(aggregate, aggregates[aggregate.id])
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
        load_aggregates([aggregate_id], clazz)[0]
      end

      # Optimised for loading lots of events and ignore snapshot events. To get the correct historical state of an
      # AggregateRoot it is necessary to be able to ignore snapshots. For a nested AggregateRoot, there will not be a
      # sequence number known, so a load_until timestamp can be used instead.
      #
      # +aggregate_id+ The id of the aggregate to be loaded
      #
      # +clazz+ Optional argument that checks if aggregate is of type +clazz+
      #
      # +load_until+ Optional argument that defines up until what point in time the AggregateRoot will be rebuilt.
      def load_aggregate_for_snapshotting(aggregate_id, clazz = nil, load_until: nil)
        fail ArgumentError, 'aggregate_id is required' if aggregate_id.blank?

        stream = Sequent
          .configuration
          .event_store
          .find_event_stream(aggregate_id)
        aggregate = Class.const_get(stream.aggregate_type).stream_from_history(stream)

        Sequent
          .configuration
          .event_store
          .stream_events_for_aggregate(aggregate_id, load_until: load_until) do |event_stream|
            aggregate.stream_from_history(event_stream)
          end

        if clazz
          fail TypeError, "#{aggregate.class} is not a #{clazz}" unless aggregate.class <= clazz
        end
        aggregate
      end

      ##
      # Loads multiple aggregates at once.
      # Returns the ones in the current Unit Of Work otherwise loads it from history.
      #
      # Note: This will load all the aggregates in memory, so querying 100s of aggregates
      # with 100s of events could cause memory issues.
      #
      # Returns all aggregates or raises +AggregateNotFound+
      # If +clazz+ is given and one of the aggregates is not of the correct type
      # a +TypeError+ is raised.
      #
      # +aggregate_ids+ The ids of the aggregates to be loaded
      # +clazz+ Optional argument that checks if all aggregates are of type +clazz+
      def load_aggregates(aggregate_ids, clazz = nil)
        fail ArgumentError, 'aggregate_ids is required' unless aggregate_ids
        return [] if aggregate_ids.empty?

        unique_ids = aggregate_ids.uniq
        result = aggregates.values_at(*unique_ids).compact
        query_ids = unique_ids - result.map(&:id)

        result += Sequent.configuration.event_store.load_events_for_aggregates(query_ids).map do |stream, events|
          aggregate_class = Class.const_get(stream.aggregate_type)
          aggregate_class.load_from_history(stream, events)
        end

        if result.count != unique_ids.count
          missing_aggregate_ids = unique_ids - result.map(&:id)
          fail AggregateNotFound, missing_aggregate_ids
        end

        if clazz
          result.each do |aggregate|
            fail TypeError, "#{aggregate.class} is not a #{clazz}" unless aggregate.class <= clazz
          end
        end

        result.map do |aggregate|
          aggregates[aggregate.id] = aggregate
        end
      end

      ##
      # Returns whether the event store has an aggregate with the given id
      def contains_aggregate?(aggregate_id)
        Sequent.configuration.event_store.stream_exists?(aggregate_id) &&
          Sequent.configuration.event_store.events_exists?(aggregate_id)
      end

      # Gets all uncommitted_events from the 'registered' aggregates
      # and stores them in the event store.
      #
      # The events given to the EventStore are ordered in loading order
      # of the different AggregateRoot's. So Events are stored
      # (and therefore published) in order in which they are `apply`-ed per AggregateRoot.
      #
      # The command is 'attached' for traceability purpose so we can see
      # which command resulted in which events.
      #
      # This is all abstracted away if you use the Sequent::Core::CommandService
      #
      def commit(command)
        updated_aggregates = aggregates.values.reject { |x| x.uncommitted_events.empty? }
        return if updated_aggregates.empty?

        streams_with_events = updated_aggregates.map do |aggregate|
          [aggregate.event_stream, aggregate.uncommitted_events]
        end
        updated_aggregates.each(&:clear_events)
        store_events command, streams_with_events
      end

      # Clears the Unit of Work.
      def clear
        Thread.current[AGGREGATES_KEY] = nil
      end

      # Clears the Unit of Work.
      #
      # A +HasUncommittedEvents+ is raised when there are uncommitted_events in the Unit of Work.
      def clear!
        fail HasUncommittedEvents if aggregates.values.any? { |x| !x.uncommitted_events.empty? }

        clear
      end

      private

      def aggregates
        Thread.current[AGGREGATES_KEY] ||= {}
      end

      def store_events(command, streams_with_events)
        Sequent.configuration.event_store.commit_events(command, streams_with_events)
      end
    end
  end
end
