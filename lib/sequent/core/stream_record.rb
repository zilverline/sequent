# frozen_string_literal: true

require 'active_record'

module Sequent
  module Core
    class EventStream
      attr_accessor :aggregate_type, :aggregate_id, :events_partition_key, :snapshot_threshold

      def initialize(aggregate_type:, aggregate_id:, events_partition_key: '', snapshot_threshold: nil)
        @aggregate_type = aggregate_type
        @aggregate_id = aggregate_id
        @events_partition_key = events_partition_key
        @snapshot_threshold = snapshot_threshold
      end
    end

    class StreamRecord < Sequent::ApplicationRecord
      self.primary_key = %i[aggregate_id]
      self.table_name = 'stream_records'

      validates_presence_of :aggregate_type, :aggregate_id
      validates_numericality_of :snapshot_threshold, only_integer: true, greater_than: 0, allow_nil: true

      has_many :event_records, foreign_key: :aggregate_id, primary_key: :aggregate_id

      def event_stream
        EventStream.new(
          aggregate_type: aggregate_type,
          aggregate_id: aggregate_id,
          snapshot_threshold: snapshot_threshold,
        )
      end

      def event_stream=(data)
        self.aggregate_type = data.aggregate_type
        self.aggregate_id = data.aggregate_id
        self.snapshot_threshold = data.snapshot_threshold
      end
    end
  end
end
