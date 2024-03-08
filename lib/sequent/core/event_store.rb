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

        q = Sequent
          .configuration
          .event_record_class
          .where(aggregate_id: aggregate_id)
          .where.not(event_type: Sequent.configuration.snapshot_event_class.name)
          .order(:sequence_number)
        q = q.where('created_at < ?', load_until) if load_until.present?
        has_events = false

        q.select('event_type, event_json').each_row do |event_hash|
          has_events = true
          event = deserialize_event(event_hash)
          block.call([stream, event])
        end
        fail ArgumentError, 'no events for this aggregate' unless has_events
      end

      def load_event(aggregate_id, sequence_number)
        Sequent.configuration.event_record_class.find_by(aggregate_id:, sequence_number:)&.event
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

        query = aggregate_ids.uniq.map { |aggregate_id| aggregate_query(aggregate_id) }.join(' UNION ALL ')
        events = Sequent.configuration.event_record_class.connection.select_all(query).map do |event_hash|
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

      def store_snapshots(snapshots)
        serializer = SnapshotRecord.new
        SnapshotRecord.insert_all!(
          snapshots.map do |snapshot|
            serializer.event = snapshot
            {
              aggregate_id: serializer.aggregate_id,
              sequence_number: serializer.sequence_number,
              created_at: serializer.created_at,
              snapshot_type: serializer.snapshot_type,
              snapshot_json: serializer.snapshot_json,
            }
          end,
        )
      end

      def load_latest_snapshot(aggregate_id)
        latest_snapshot = SnapshotRecord.where(aggregate_id:).order(:sequence_number).last
        latest_snapshot&.event
      end

      # Deletes all snapshots for aggregate_id with a sequence_number lower than the specified sequence number.
      def delete_snapshots_before(aggregate_id, sequence_number)
        SnapshotRecord.where(aggregate_id: aggregate_id).where('sequence_number < ?', sequence_number).delete_all
      end

      def aggregate_query(aggregate_id)
        <<~SQL.chomp
          (
          WITH snapshot AS (SELECT *
                              FROM #{quote_table_name Sequent.configuration.snapshot_record_class.table_name}
                             WHERE aggregate_id = #{quote(aggregate_id)}
                             ORDER BY sequence_number DESC
                             LIMIT 1)
          SELECT snapshot_type AS event_type, snapshot_json AS event_json, 0 AS sequence_number
            FROM snapshot
           UNION ALL
          SELECT event_type, event_json, sequence_number
            FROM #{quote_table_name Sequent.configuration.event_record_class.table_name} AS o
           WHERE aggregate_id = #{quote(aggregate_id)}
             AND sequence_number >= COALESCE((SELECT sequence_number FROM snapshot), 0)
          ORDER BY sequence_number ASC
          )
        SQL
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
        snapshot_table = quote_table_name Sequent.configuration.snapshot_record_class.table_name
        query = <<~SQL.chomp
          SELECT aggregate_id
            FROM #{stream_table} stream
           WHERE aggregate_id::varchar > COALESCE(#{quote last_aggregate_id}, '')
             AND snapshot_threshold IS NOT NULL
             AND snapshot_threshold <= (
                   (SELECT MAX(events.sequence_number) FROM #{event_table} events WHERE stream.aggregate_id = events.aggregate_id) -
                   COALESCE((SELECT MAX(snapshots.sequence_number) FROM #{snapshot_table} snapshots WHERE stream.aggregate_id = snapshots.aggregate_id), 0))
           ORDER BY aggregate_id
           LIMIT #{quote limit}
           FOR UPDATE
        SQL
        Sequent.configuration.event_record_class.connection.select_all(query).map { |x| x['aggregate_id'] }
      end

      def find_event_stream(aggregate_id)
        record = Sequent.configuration.stream_record_class.where(aggregate_id: aggregate_id).first
        record&.event_stream
      end

      def permanently_delete_event_stream(aggregate_id)
        Sequent.configuration.event_record_class.where(aggregate_id: aggregate_id).delete_all
        Sequent.configuration.stream_record_class.where(aggregate_id: aggregate_id).delete_all
      end

      def permanently_delete_commands_without_events(where_clause)
        CommandRecord
          .where(where_clause)
          .where('NOT EXISTS (SELECT 1 FROM event_records WHERE command_record_id = command_records.id)')
          .delete_all
      end

      private

      def event_types
        @event_types = if Sequent.configuration.event_store_cache_event_types
                         ThreadSafe::Cache.new
                       else
                         NoEventTypesCache.new
                       end
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
        record = Sequent.configuration.event_record_class.new
        record.event_type = event_hash.fetch('event_type')
        record.event_json =
          if record.serialize_json?
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
        command_record = CommandRecord.create!(command: command)
        streams = streams_with_events.map do |event_stream, _|
          {
            aggregate_id: event_stream.aggregate_id,
            aggregate_type: event_stream.aggregate_type,
            snapshot_threshold: event_stream.snapshot_threshold,
          }
        end.uniq { |s| s[:aggregate_id] }
        Sequent.configuration.stream_record_class
          .upsert_all(streams, unique_by: :aggregate_id, update_only: %i[snapshot_threshold])

        event_records = streams_with_events.flat_map do |_, uncommitted_events|
          uncommitted_events.map do |event|
            record = Sequent.configuration.event_record_class.new
            record.command_record_id = command_record.id
            record.event = event
            record.attributes.slice(*column_names)
          end
        end
        Sequent.configuration.event_record_class.insert_all!(event_records) if event_records.present?
      rescue ActiveRecord::RecordNotUnique
        raise OptimisticLockingError
      end
    end
  end
end
