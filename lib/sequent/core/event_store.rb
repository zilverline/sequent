# frozen_string_literal: true

require 'forwardable'
require_relative 'event_record'
require_relative 'sequent_oj'

module Sequent
  module Core
    class EventStore
      include ActiveRecord::ConnectionAdapters::Quoting
      extend Forwardable

      class OptimisticLockingError < RuntimeError
      end

      class DeserializeEventError < RuntimeError
        attr_reader :event_hash

        def initialize(event_hash)
          super()
          @event_hash = event_hash
        end

        def message
          "Event hash: #{event_hash.inspect}\nCause: #{cause.inspect}"
        end
      end

      ##
      # Disables event type caching (ie. for in development).
      #
      class NoEventTypesCache
        def fetch_or_store(event_type)
          yield(event_type)
        end
      end

      ##
      # Stores the events in the EventStore and publishes the events
      # to the registered event_handlers.
      #
      # The events are published according to the order in
      # the tail of the given `streams_with_events` array pair.
      #
      # @param command The command that caused the Events
      # @param streams_with_events is an enumerable of pairs from
      #   `StreamRecord` to arrays ordered uncommitted `Event`s.
      #
      def commit_events(command, streams_with_events)
        fail ArgumentError, 'command is required' if command.nil?

        Sequent.logger.debug("[EventStore] Committing events for command #{command.class}")

        store_events(command, streams_with_events)
        publish_events(streams_with_events.flat_map { |_, events| events })
      end

      ##
      # Returns all events for the AggregateRoot ordered by sequence_number, disregarding snapshot events.
      #
      # This streaming is done in batches to prevent loading many events in memory all at once. A usecase for ignoring
      # the snapshots is when events of a nested AggregateRoot need to be loaded up until a certain moment in time.
      #
      # @param aggregate_id Aggregate id of the AggregateRoot
      # @param load_until The timestamp up until which you want to built the aggregate. Optional.
      # @param &block Block that should be passed to handle the batches returned from this method
      def stream_events_for_aggregate(aggregate_id, load_until: nil, &block)
        stream = find_event_stream(aggregate_id)
        fail ArgumentError, 'no stream found for this aggregate' if stream.blank?

        has_events = false

        # PostgreSQLCursor::Cursor does not support bind parameters, so bind parameters manually instead.
        sql = ActiveRecord::Base.sanitize_sql_array(
          [
            "SELECT * FROM load_events(:aggregate_ids, :snapshot_event_type, FALSE, :load_until)", {
              aggregate_ids: [aggregate_id].to_json,
              snapshot_event_type: Sequent.configuration.snapshot_event_class.name,
              load_until: load_until
            }
          ]
        )

        PostgreSQLCursor::Cursor.new(sql, { connection: connection }).each_row do |event_hash|
          has_events = true
          event = deserialize_event(event_hash)
          block.call([stream, event])
        end
        fail ArgumentError, 'no events for this aggregate' unless has_events
      end

      ##
      # Returns all events for the aggregate ordered by sequence_number, loading them from the latest snapshot
      # event onwards, if a snapshot is present
      #
      def load_events(aggregate_id)
        load_events_for_aggregates([aggregate_id])[0]
      end

      def load_events_for_aggregates(aggregate_ids)
        return [] if aggregate_ids.none?

        streams = Sequent.configuration.stream_record_class.where(aggregate_id: aggregate_ids)

        events = query_events(aggregate_ids).map do |event_hash|
          deserialize_event(event_hash)
        end

        events
          .group_by(&:aggregate_id)
          .map do |aggregate_id, es|
            [
              streams.find do |stream_record|
                stream_record.aggregate_id == aggregate_id
              end.event_stream,
              es,
            ]
          end
      end

      def stream_exists?(aggregate_id)
        Sequent.configuration.stream_record_class.exists?(aggregate_id: aggregate_id)
      end

      def events_exists?(aggregate_id)
        Sequent.configuration.event_record_class.exists?(aggregate_id: aggregate_id)
      end

      ##
      # Replays all events in the event store to the registered event_handlers.
      #
      # @param block that returns the events.
      # <b>DEPRECATED:</b> use <tt>replay_events_from_cursor</tt> instead.
      def replay_events
        warn '[DEPRECATION] `replay_events` is deprecated in favor of `replay_events_from_cursor`'
        events = yield.map { |event_hash| deserialize_event(event_hash) }
        publish_events(events)
      end

      ##
      # Replays all events on an `EventRecord` cursor from the given block.
      #
      # Prefer this replay method if your db adapter supports cursors.
      #
      # @param get_events lambda that returns the events cursor
      # @param on_progress lambda that gets called on substantial progress
      def replay_events_from_cursor(get_events:, block_size: 2000,
                                    on_progress: PRINT_PROGRESS)
        progress = 0
        cursor = get_events.call
        ids_replayed = []
        cursor.each_row(block_size: block_size).each do |record|
          event = deserialize_event(record)
          publish_events([event])
          progress += 1
          ids_replayed << record['id']
          if progress % block_size == 0
            on_progress[progress, false, ids_replayed]
            ids_replayed.clear
          end
        end
        on_progress[progress, true, ids_replayed]
      end

      PRINT_PROGRESS = ->(progress, done, _) do
        if done
          Sequent.logger.debug "Done replaying #{progress} events"
        else
          Sequent.logger.debug "Replayed #{progress} events"
        end
      end

      ##
      # Returns the ids of aggregates that need a new snapshot.
      #
      def aggregates_that_need_snapshots(last_aggregate_id, limit = 10)
        stream_table = quote_table_name Sequent.configuration.stream_record_class.table_name
        event_table = quote_table_name Sequent.configuration.event_record_class.table_name
        query = "SELECT aggregate_id FROM aggregates_that_need_snapshots($1, $2, $3)"
        connection.exec_query(query, "aggregates_that_need_snapshots", [last_aggregate_id, limit, Sequent.configuration.snapshot_event_class.name]).map { |x| x['aggregate_id'] }
      end

      def find_event_stream(aggregate_id)
        record = Sequent.configuration.stream_record_class.where(aggregate_id: aggregate_id).first
        record&.event_stream
      end

      private

      def event_types
        @event_types = if Sequent.configuration.event_store_cache_event_types
                         ThreadSafe::Cache.new
                       else
                         NoEventTypesCache.new
                       end
      end

      def connection
        Sequent.configuration.event_record_class.connection
      end

      def query_events(aggregate_ids, use_snapshots = true, load_until = nil)
        query = "SELECT event_type, event_json FROM load_events($1::JSONB, $2, $3, $4)"
        connection.exec_query(query, "load_events", [aggregate_ids.to_json, Sequent.configuration.snapshot_event_class.name, use_snapshots, load_until])
      end

      def column_names
        @column_names ||= Sequent
          .configuration
          .event_record_class
          .column_names
          .reject { |c| c == primary_key_event_records }
      end

      def primary_key_event_records
        @primary_key_event_records ||= Sequent.configuration.event_record_class.primary_key
      end

      def deserialize_event(event_hash)
        event_type = event_hash.fetch('event_type')
        event_json = Sequent::Core::Oj.strict_load(event_hash.fetch('event_json'))
        resolve_event_type(event_type).deserialize_from_json(event_json)
      rescue StandardError
        raise DeserializeEventError, event_hash
      end

      def resolve_event_type(event_type)
        event_types.fetch_or_store(event_type) { |k| Class.const_get(k) }
      end

      def publish_events(events)
        Sequent.configuration.event_publisher.publish_events(events)
      end

      def store_events(command, streams_with_events = [])
        command_record = CommandRecord.create!(command: command)
        json = streams_with_events.map do |event_stream, uncommitted_events|
          stream = Oj.strict_load(Oj.dump(event_stream))
          [stream, uncommitted_events.map { |event|
             r = Sequent::Core::Oj.strict_load(Sequent::Core::Oj.dump(event))
             # Since Rails uses `TIMESTAMP WITHOUT TIME ZONE` we need to manually convert database timestamps to UTC on serialization
             r['created_at'] = event.created_at.utc
             r['event_type'] = event.class.name
             r
           }]
        end.to_json
        connection.exec_update("CALL store_events($1, $2)", "store_events", [command_record.id, json])
      rescue ActiveRecord::RecordNotUnique
        raise OptimisticLockingError
      end
    end
  end
end
