# frozen_string_literal: true

require 'active_record'
require_relative '../application_record'

module Sequent
  module Internal
    class PartitionedAggregate < Sequent::ApplicationRecord
      self.table_name = :aggregates
      self.primary_key = %i[aggregate_id]

      belongs_to :aggregate_type
      has_many :events,
               inverse_of: :aggregate,
               class_name: :PartitionedEvent,
               primary_key: %i[events_partition_key aggregate_id],
               query_constraints: %i[partition_key aggregate_id]
    end
  end
end
