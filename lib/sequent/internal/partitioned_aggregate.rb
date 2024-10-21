# frozen_string_literal: true

require 'active_record'
require_relative '../application_record'

module Sequent
  module Internal
    class PartitionedAggregate < Sequent::ApplicationRecord
      self.table_name = :aggregates
      self.primary_key = %i[aggregate_id]

      belongs_to :aggregate_type
      if Gem.loaded_specs['activerecord'].version < Gem::Version.create('7.2')
        has_many :partitioned_events,
                 inverse_of: :partitioned_aggregate,
                 primary_key: %w[events_partition_key aggregate_id],
                 query_constraints: %w[partition_key aggregate_id]
      else
        has_many :partitioned_events,
                 inverse_of: :partitioned_aggregate,
                 primary_key: %i[events_partition_key aggregate_id],
                 foreign_key: %i[partition_key aggregate_id]
      end
    end
  end
end
