# frozen_string_literal: true

require 'forwardable'
require_relative 'event_record'
require_relative 'helpers/pgsql_helpers'
require_relative 'sequent_oj'
require_relative 'snapshot_record'
require_relative 'snapshot_store'

module Sequent
  module Core
    class AggregateKeyNotUniqueError < RuntimeError
      attr_reader :aggregate_type, :aggregate_id

      def self.unique_key_error_message?(message)
        message =~ /duplicate unique key value for aggregate/
      end

      def initialize(message)
        super

        match = message.match(
          # rubocop:disable Layout/LineLength
          /aggregate (\p{Upper}\p{Alnum}*(?:::\p{Upper}\p{Alnum}*)*) (\p{XDigit}{8}-\p{XDigit}{4}-\p{XDigit}{4}-\p{XDigit}{4}-\p{XDigit}{12})/,
          # rubocop:enable Layout/LineLength
        )
        if match
          @aggregate_type = match[1]
          @aggregate_id = match[2]
        end
      end
    end

    class EventStore
      include Helpers::PgsqlHelpers
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
        event_hash = query_function(connection, 'load_event', [aggregate_id, sequence_number]).first
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

      def position_mark
        connection.exec_query('SELECT pg_current_snapshot()::text AS mark')[0]['mark']
      end

      def load_events_since_marked_position(mark)
        events = connection.execute(
          Sequent.configuration.event_record_class
            .where(<<~SQL, {mark:})
              xact_id >= pg_snapshot_xmin(CAST(:mark AS pg_snapshot))::text::bigint
                AND NOT pg_visible_in_snapshot(xact_id::text::xid8, CAST(:mark AS pg_snapshot))
            SQL
            .select('*, pg_current_snapshot()::text AS mark')
            .to_sql,
        ).to_a

        return [[], mark] if events.empty?

        [
          events.map { |hash| deserialize_event(hash) },
          events[0]['mark'],
        ]
      end

      # Returns an enumerator that yields aggregate ids in blocks of `group_size` arrays. Optionally the
      # aggregate root type can be specified (as a string) to only yield aggregate ids of the indicated type.
      def event_streams_enumerator(aggregate_type: nil, group_size: 100)
        Enumerator.new do |yielder|
          last_aggregate_id = nil
          loop do
            aggregate_rows = ActiveRecord::Base.connection.exec_query(
              'SELECT aggregate_id
                 FROM aggregates
                WHERE ($1::text IS NULL OR aggregate_type_id = (SELECT id FROM aggregate_types WHERE type = $1))
                  AND ($3::uuid IS NULL OR aggregate_id > $3)
                ORDER BY 1
                LIMIT $2',
              'aggregates_to_update',
              [
                aggregate_type,
                group_size,
                last_aggregate_id,
              ],
            ).to_a
            break if aggregate_rows.empty?

            last_aggregate_id = aggregate_rows.last['aggregate_id']

            yielder << aggregate_rows.map { |x| x['aggregate_id'] }
          end
        end
      end

      def update_unique_keys(event_streams)
        fail ArgumentError, 'array of stream records expected' unless event_streams.all? { |x| x.is_a?(EventStream) }

        call_procedure(connection, 'update_unique_keys', [event_streams.to_json])
      rescue ActiveRecord::RecordNotUnique => e
        if AggregateKeyNotUniqueError.unique_key_error_message?(e.message)
          raise AggregateKeyNotUniqueError, e.message
        else
          raise OptimisticLockingError
        end
      end

      def permanently_delete_event_stream(aggregate_id)
        permanently_delete_event_streams([aggregate_id])
      end

      def permanently_delete_event_streams(aggregate_ids)
        call_procedure(connection, 'permanently_delete_event_streams', [aggregate_ids.to_json])
      end

      def permanently_delete_commands_without_events(aggregate_id:)
        fail ArgumentError, 'aggregate_id must be specified' unless aggregate_id

        call_procedure(connection, 'permanently_delete_commands_without_events', [aggregate_id])
      end

      private

      def connection
        Sequent.configuration.event_record_class.connection
      end

      def query_events(aggregate_ids, use_snapshots = true, load_until = nil)
        query_function(connection, 'load_events', [aggregate_ids.to_json, use_snapshots, load_until])
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
        call_procedure(
          connection,
          'store_events',
          [
            Sequent::Core::Oj.dump(command_record),
            Sequent::Core::Oj.dump(events),
          ],
        )
      rescue ActiveRecord::RecordNotUnique => e
        if AggregateKeyNotUniqueError.unique_key_error_message?(e.message)
          raise AggregateKeyNotUniqueError, e.message
        else
          raise OptimisticLockingError
        end
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
