# frozen_string_literal: true

require 'active_record'

module Sequent
  module Core
    EventStream = Data.define(
      :aggregate_type,
      :aggregate_id,
      :events_partition_key,
      :snapshot_outdated_at,
      :snapshot_version,
      :unique_keys,
    ) do
      def initialize(aggregate_type:, aggregate_id:, events_partition_key: '', snapshot_outdated_at: nil,
                     snapshot_version: 1, unique_keys: {})
        super
      end
    end

    class AggregateUniqueKey < Sequent::ApplicationRecord
      self.primary_key = %i[aggregate_id scope]
      self.table_name = 'aggregate_unique_keys'

      validates_presence_of :aggregate_id, :scope, :key

      belongs_to :stream_record, foreign_key: :aggregate_id, primary_key: :aggregate_id
    end

    class StreamRecord < Sequent::ApplicationRecord
      self.primary_key = %i[aggregate_id]
      self.table_name = 'stream_records'
      self.ignored_columns = %w[snapshot_threshold]

      validates_presence_of :aggregate_type, :aggregate_id

      has_many :event_records, foreign_key: :aggregate_id, primary_key: :aggregate_id
      has_many :aggregate_unique_keys, foreign_key: :aggregate_id, primary_key: :aggregate_id

      def event_stream
        EventStream.new(
          aggregate_type:,
          aggregate_id:,
          events_partition_key:,
          unique_keys: aggregate_unique_keys.to_h { |key| [key.scope.to_sym, key.key] },
        )
      end

      def event_stream=(data)
        self.aggregate_type = data.aggregate_type
        self.aggregate_id = data.aggregate_id
        self.events_partition_key = data.events_partition_key
      end
    end
  end
end
