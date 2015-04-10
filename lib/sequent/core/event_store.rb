require 'oj'
require_relative 'event_record'

module Sequent
  module Core
    class EventStoreConfiguration
      attr_accessor :record_class, :event_handlers

      def initialize(record_class = Sequent::Core::EventRecord, event_handlers = [])
        @record_class = record_class
        @event_handlers = event_handlers
      end
    end

    class EventStore
      include ActiveRecord::ConnectionAdapters::Quoting

      class << self
        attr_accessor :configuration,
                      :instance
      end

      # Creates a new EventStore and overwrites all existing config.
      # The new EventStore can be retrieved via the +EventStore.instance+ method.
      #
      # If you don't want a singleton you can always instantiate it yourself using the +EventStore.new+.
      def self.configure
        self.configuration = EventStoreConfiguration.new
        yield(configuration) if block_given?
        EventStore.instance = EventStore.new(configuration)
      end

      def initialize(configuration = EventStoreConfiguration.new)
        @record_class = configuration.record_class
        @event_handlers = configuration.event_handlers
        @event_types = ThreadSafe::Cache.new
      end

      ##
      # Stores the events in the EventStore and publishes the events
      # to the registered event_handlers.
      #
      # Events is a hash or array of pairs from `StreamRecord` to
      # arrays of uncommitted `Event`s.
      #
      def commit_events(command, streams_with_events)
        store_events(command, streams_with_events)
        publish_events(streams_with_events.flat_map {|_, events| events}, @event_handlers)
      end

      ##
      # Returns all events for the aggregate ordered by sequence_number
      #
      def load_events(aggregate_id)
        stream = StreamRecord.where(aggregate_id: aggregate_id).first!
        events = @record_class.connection.select_all(%Q{
SELECT event_type, event_json
  FROM #{quote_table_name @record_class.table_name}
 WHERE aggregate_id = #{quote aggregate_id}
   AND sequence_number >= COALESCE((SELECT MAX(sequence_number)
                                      FROM #{quote_table_name @record_class.table_name}
                                     WHERE event_type = #{quote SnapshotEvent.name}
                                       AND aggregate_id = #{quote aggregate_id}), 0)
 ORDER BY sequence_number ASC, (CASE event_type WHEN #{quote SnapshotEvent.name} THEN 0 ELSE 1 END) ASC
}).map! do |event_hash|
          deserialize_event(event_hash)
        end
        [stream, events]
      end

      ##
      # Replays all events in the event store to the registered event_handlers.
      #
      # @param block that returns the events.
      def replay_events
        events = yield.map {|event_hash| deserialize_event(event_hash)}
        publish_events(events, @event_handlers)
      end

      def aggregates_that_need_snapshots(limit: 10, last_aggregate_id: nil)
        query = %Q{
SELECT aggregate_id
  FROM #{quote_table_name @record_class.table_name} events
 WHERE aggregate_id > COALESCE(#{quote last_aggregate_id}, '')
   AND event_type <> #{quote SnapshotEvent.name}
 GROUP BY aggregate_id
HAVING (MAX(sequence_number)
        - (COALESCE((SELECT MAX(sequence_number)
                       FROM #{quote_table_name @record_class.table_name} snapshots
                      WHERE event_type = #{quote SnapshotEvent.name}
                        AND snapshots.aggregate_id = events.aggregate_id), 0)))
       >= (SELECT snapshot_threshold
             FROM #{quote_table_name StreamRecord.table_name} streams
            WHERE events.aggregate_id = streams.aggregate_id)
 ORDER BY aggregate_id
 LIMIT #{quote limit}
}
        @record_class.connection.select_all(query).map {|x| x['aggregate_id']}
      end

      protected
      def record_class
        @record_class
      end

      private

      def deserialize_event(event_hash)
        event_type = event_hash.fetch("event_type")
        event_json = Oj.strict_load(event_hash.fetch("event_json"))
        resolve_event_type(event_type).deserialize_from_json(event_json)
      end

      def resolve_event_type(event_type)
        @event_types.fetch_or_store(event_type) { |k| constant_get(k) }
      end

      # A better const get (via https://www.ruby-forum.com/topic/103276)
      def constant_get(hierachy)
        ancestors = hierachy.split(%r/::/)
        parent = Object
        while ((child = ancestors.shift))
          klass = parent.const_get child
          parent = klass
        end
        klass
      end

      def publish_events(events, event_handlers)
        events.each do |event|
          event_handlers.each do |handler|
            handler.handle_message event
          end
        end
      end

      def store_events(command, streams_with_events = [])
        command_record = CommandRecord.create!(:command => command)
        streams_with_events.each do |stream_record, uncommitted_events|
          stream_record.save! unless stream_record.id.present?
          uncommitted_events.each do |event|
            @record_class.create!(:command_record => command_record, :stream_record => stream_record, :event => event)
          end
        end
      end

    end

  end
end
