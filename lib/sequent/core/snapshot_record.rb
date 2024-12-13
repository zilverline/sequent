# frozen_string_literal: true

require 'active_record'
require_relative 'sequent_oj'
require_relative '../application_record'

module Sequent
  module Core
    class SnapshotRecord < Sequent::ApplicationRecord
      include SerializesEvent

      self.primary_key = %i[aggregate_id sequence_number]
      self.table_name = 'snapshot_records'

      belongs_to :stream_record, foreign_key: :aggregate_id, primary_key: :aggregate_id

      validates_presence_of :aggregate_id, :sequence_number, :snapshot_json, :stream_record
      validates_numericality_of :sequence_number, only_integer: true, greater_than: 0

      private

      def event_type
        snapshot_type
      end

      def event_type=(type)
        self.snapshot_type = type
      end

      def event_json
        snapshot_json
      end

      def event_json=(json)
        self.snapshot_json = json
      end

      def serialize_json?
        json_column_type = self.class.columns_hash['snapshot_json'].sql_type_metadata.type
        %i[json jsonb].exclude? json_column_type
      end
    end
  end
end
