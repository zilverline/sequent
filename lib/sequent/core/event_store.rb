# frozen_string_literal: true

require 'forwardable'
require_relative 'event_record'
require_relative 'sequent_oj'
require_relative 'snapshot_record'

module Sequent
  module Core
    module SnapshotStore
      def store_snapshots(snapshots)
        json = Sequent::Core::Oj.dump(
          snapshots.map do |snapshot|
            {
              aggregate_id: snapshot.aggregate_id,
              sequence_number: snapshot.sequence_number,
              created_at: snapshot.created_at,
              snapshot_type: snapshot.class.name,
              snapshot_json: snapshot,
            }
          end,
        )
        connection.exec_update(
          'CALL store_snapshots($1)',
          'store_snapshots',
          [json],
        )
      end

      def load_latest_snapshot(aggregate_id)
        snapshot_hash = connection.exec_query(
          'SELECT * FROM load_latest_snapshot($1)',
          'load_latest_snapshot',
          [aggregate_id],
        ).first
        deserialize_event(snapshot_hash) unless snapshot_hash['aggregate_id'].nil?
      end

      # Deletes all snapshots for all aggregates
      def delete_all_snapshots
        connection.exec_update(
          'CALL delete_all_snapshots()',
          'delete_all_snapshots',
          [],
        )
      end

      # Deletes all snapshots for aggregate_id with a sequence_number lower than the specified sequence number.
      def delete_snapshots_before(aggregate_id, sequence_number)
        connection.exec_update(
          'CALL delete_snapshots_before($1, $2)',
          'delete_snapshots_before',
          [aggregate_id, sequence_number],
        )
      end

      # Marks an aggregate for snapshotting. Marked aggregates will be
      # picked up by the background snapshotting task. Another way to
      # mark aggregates for snapshotting is to pass the
      # *EventStream#snapshot_outdated_at* property to the
      # *#store_events* method as is done automatically by the
      # *AggregateRepository* based on the aggregate's
      # *snapshot_threshold*.
      def mark_aggregate_for_snapshotting(aggregate_id, snapshot_outdated_at = Time.now)
        connection.exec_update(<<~EOS, 'mark_aggregate_for_snapshotting', [aggregate_id, snapshot_outdated_at])
          INSERT INTO aggregates_that_need_snapshots AS row (aggregate_id, snapshot_outdated_at)
          VALUES ($1, $2)
              ON CONFLICT (aggregate_id) DO UPDATE
             SET snapshot_outdated_at = LEAST(row.snapshot_outdated_at, EXCLUDED.snapshot_outdated_at)
        EOS
      end

      # Stops snapshotting the specified aggregate. Any existing
      # snapshots for this aggregate are also deleted.
      def clear_aggregate_for_snapshotting(aggregate_id)
        connection.exec_update(
          'DELETE FROM aggregates_that_need_snapshots WHERE aggregate_id = $1',
          'clear_aggregate_for_snapshotting',
          [aggregate_id],
        )
      end

      # Stops snapshotting all aggregates where the last event
      # occurred before the indicated timestamp. Any existing
      # snapshots for this aggregate are also deleted.
      def clear_aggregates_for_snapshotting_with_last_event_before(timestamp)
        connection.exec_update(<<~EOS, 'clear_aggregates_for_snapshotting_with_last_event_before', [timestamp])
          DELETE FROM aggregates_that_need_snapshots s
           WHERE NOT EXISTS (SELECT *
                               FROM aggregates a
                               JOIN events e ON (a.aggregate_id, a.events_partition_key) = (e.aggregate_id, e.partition_key)
                              WHERE a.aggregate_id = s.aggregate_id AND e.created_at >= $1)
        EOS
      end

      ##
      # Returns the ids of aggregates that need a new snapshot.
      #
      def aggregates_that_need_snapshots(last_aggregate_id, limit = 10)
        connection.exec_query(
          'SELECT aggregate_id FROM aggregates_that_need_snapshots($1, $2)',
          'aggregates_that_need_snapshots',
          [last_aggregate_id, limit],
        ).map { |x| x['aggregate_id'] }
      end

      def aggregates_that_need_snapshots_ordered_by_priority(limit = 10)
        connection.exec_query(
          'SELECT aggregate_id FROM aggregates_that_need_snapshots_ordered_by_priority($1)',
          'aggregates_that_need_snapshots',
          [limit],
        ).map { |x| x['aggregate_id'] }
      end
    end

    class EventStore
      include SnapshotStore
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
      # Returns all events for the AggregateRoot ordered by sequence_number, disregarding snapshots.
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
            'SELECT * FROM load_events(:aggregate_ids, FALSE, :load_until)',
            {
              aggregate_ids: [aggregate_id].to_json,
              load_until: load_until,
            },
          ],
        )

        PostgreSQLCursor::Cursor.new(sql, {connection: connection}).each_row do |event_hash|
          has_events = true
          event = deserialize_event(event_hash)
          block.call([stream, event])
        end
        fail ArgumentError, 'no events for this aggregate' unless has_events
      end

      def load_event(aggregate_id, sequence_number)
        event_hash = connection.exec_query(
          'SELECT * FROM load_event($1, $2)',
          'load_event',
          [aggregate_id, sequence_number],
        ).first
        deserialize_event(event_hash) if event_hash
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

        query_events(aggregate_ids)
          .group_by { |row| row['aggregate_id'] }
          .values
          .map do |rows|
            [
              EventStream.new(
                aggregate_type: rows.first['aggregate_type'],
                aggregate_id: rows.first['aggregate_id'],
                events_partition_key: rows.first['events_partition_key'],
              ),
              rows.map { |row| deserialize_event(row) },
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
          ids_replayed << record['aggregate_id']
          if progress % block_size == 0
            on_progress[progress, false, ids_replayed]
            ids_replayed.clear
          end
        end
        on_progress[progress, true, ids_replayed]
      end

      PRINT_PROGRESS = ->(progress, done, _) do
        next unless Sequent.logger.debug?

        if done
          Sequent.logger.debug("Done replaying #{progress} events")
        else
          Sequent.logger.debug("Replayed #{progress} events")
        end
      end

      def find_event_stream(aggregate_id)
        record = Sequent.configuration.stream_record_class.where(aggregate_id: aggregate_id).first
        record&.event_stream
      end

      def permanently_delete_event_stream(aggregate_id)
        permanently_delete_event_streams([aggregate_id])
      end

      def permanently_delete_event_streams(aggregate_ids)
        connection.exec_update(
          'CALL permanently_delete_event_streams($1)',
          'permanently_delete_event_streams',
          [aggregate_ids.to_json],
        )
      end

      def permanently_delete_commands_without_events(aggregate_id: nil, organization_id: nil)
        unless aggregate_id || organization_id
          fail ArgumentError, 'aggregate_id and/or organization_id must be specified'
        end

        connection.exec_update(
          'CALL permanently_delete_commands_without_events($1, $2)',
          'permanently_delete_commands_without_events',
          [aggregate_id, organization_id],
        )
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
        connection.exec_query(
          'SELECT * FROM load_events($1::JSONB, $2, $3)',
          'load_events',
          [aggregate_ids.to_json, use_snapshots, load_until],
        )
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
        should_serialize_json = Sequent.configuration.event_record_class.serialize_json?
        record = Sequent.configuration.event_record_class.new
        record.event_type = event_hash.fetch('event_type')
        record.event_json =
          if should_serialize_json
            event_hash.fetch('event_json')
          else
            # When the column type is JSON or JSONB the event record
            # class expects the JSON to be deserialized into a hash
            # already.
            Sequent::Core::Oj.strict_load(event_hash.fetch('event_json'))
          end
        record.event
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
        command_record = {
          created_at: convert_timestamp(command.created_at&.to_time || Time.now),
          command_type: command.class.name,
          command_json: command,
        }

        events = streams_with_events.map do |stream, uncommitted_events|
          [
            Sequent::Core::Oj.strict_load(Sequent::Core::Oj.dump(stream)),
            uncommitted_events.map do |event|
              {
                created_at: convert_timestamp(event.created_at.to_time),
                event_type: event.class.name,
                event_json: event,
              }
            end,
          ]
        end
        connection.exec_update(
          'CALL store_events($1, $2)',
          'store_events',
          [
            Sequent::Core::Oj.dump(command_record),
            Sequent::Core::Oj.dump(events),
          ],
        )
      rescue ActiveRecord::RecordNotUnique
        raise OptimisticLockingError
      end

      def convert_timestamp(timestamp)
        # Since ActiveRecord uses `TIMESTAMP WITHOUT TIME ZONE`
        # we need to manually convert database timestamps to the
        # ActiveRecord default time zone on serialization.
        ActiveRecord.default_timezone == :utc ? timestamp.getutc : timestamp.getlocal
      end
    end
  end
end
