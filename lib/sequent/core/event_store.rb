require 'forwardable'
require_relative 'event_record'
require_relative 'sequent_oj'

module Sequent
  module Core

    class EventStore
      include ActiveRecord::ConnectionAdapters::Quoting
      extend Forwardable

      attr_accessor :configuration
      def_delegators :@configuration, :stream_record_class, :event_record_class, :snapshot_event_class, :event_handlers

      def initialize(configuration = Sequent.configuration)
        self.configuration = configuration
        @event_types = ThreadSafe::Cache.new
      end

      ##
      # Stores the events in the EventStore and publishes the events
      # to the registered event_handlers.
      #
      # Streams_with_Events is an enumerable of pairs from
      # `StreamRecord` to arrays of uncommitted `Event`s.
      #
      def commit_events(command, streams_with_events)
        store_events(command, streams_with_events)
        publish_events(streams_with_events.flat_map {|_, events| events}, event_handlers)
      end

      ##
      # Returns all events for the aggregate ordered by sequence_number
      #
      def load_events(aggregate_id)
        stream = stream_record_class.where(aggregate_id: aggregate_id).first!
        events = event_record_class.connection.select_all(%Q{
SELECT event_type, event_json
  FROM #{quote_table_name event_record_class.table_name}
 WHERE aggregate_id = #{quote aggregate_id}
   AND sequence_number >= COALESCE((SELECT MAX(sequence_number)
                                      FROM #{quote_table_name event_record_class.table_name}
                                     WHERE event_type = #{quote snapshot_event_class.name}
                                       AND aggregate_id = #{quote aggregate_id}), 0)
 ORDER BY sequence_number ASC, (CASE event_type WHEN #{quote snapshot_event_class.name} THEN 0 ELSE 1 END) ASC
}).map! do |event_hash|
          deserialize_event(event_hash)
        end
        [stream.event_stream, events]
      end

      ##
      # Replays all events in the event store to the registered event_handlers.
      #
      # @param block that returns the events.
      def replay_events
        events = yield.map {|event_hash| deserialize_event(event_hash)}
        publish_events(events, event_handlers)
      end

      ##
      # Returns the ids of aggregates that need a new snapshot.
      #
      def aggregates_that_need_snapshots(last_aggregate_id, limit = 10)
        stream_table = quote_table_name stream_record_class.table_name
        event_table = quote_table_name event_record_class.table_name
        query = %Q{
SELECT aggregate_id
  FROM #{stream_table} stream
 WHERE aggregate_id > COALESCE(#{quote last_aggregate_id}, '')
   AND snapshot_threshold IS NOT NULL
   AND snapshot_threshold <= (
         (SELECT MAX(events.sequence_number) FROM #{event_table} events WHERE events.event_type <> #{quote snapshot_event_class.name} AND stream.aggregate_id = events.aggregate_id) -
         COALESCE((SELECT MAX(snapshots.sequence_number) FROM #{event_table} snapshots WHERE snapshots.event_type = #{quote snapshot_event_class.name} AND stream.aggregate_id = snapshots.aggregate_id), 0))
 ORDER BY aggregate_id
 LIMIT #{quote limit}
}
        event_record_class.connection.select_all(query).map {|x| x['aggregate_id']}
      end

      def find_event_stream(aggregate_id)
        record = stream_record_class.where(aggregate_id: aggregate_id).first
        if record
          record.event_stream
        else
          nil
        end
      end

      private

      def deserialize_event(event_hash)
        event_type = event_hash.fetch("event_type")
        event_json = Sequent::Core::Oj.strict_load(event_hash.fetch("event_json"))
        resolve_event_type(event_type).deserialize_from_json(event_json)
      end

      def resolve_event_type(event_type)
        @event_types.fetch_or_store(event_type) { |k| Class.const_get(k) }
      end

      def publish_events(events, event_handlers)
        events.each do |event|
          event_handlers.each do |handler|
            handler.handle_message event
          end
        end
      end

      def store_events(command, streams_with_events = [])
        command_record = CommandRecord.create!(command: command)
        streams_with_events.each do |event_stream, uncommitted_events|
          unless event_stream.stream_record_id
            stream_record = stream_record_class.new
            stream_record.event_stream = event_stream
            stream_record.save!
            event_stream.stream_record_id = stream_record.id
          end
          uncommitted_events.each do |event|
            event_record_class.create!(command_record: command_record, stream_record_id: event_stream.stream_record_id, event: event)
          end
        end
      end
    end

  end
end
