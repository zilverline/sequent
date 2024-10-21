# frozen_string_literal: true

require 'active_record'
require_relative '../application_record'

module Sequent
  module Internal
    class PartitionedEvent < Sequent::ApplicationRecord
      self.table_name = :events
      self.primary_key = %i[partition_key aggregate_id sequence_number]

      belongs_to :event_type
      belongs_to :partitioned_command,
                 inverse_of: :partitioned_events,
                 foreign_key: :command_id
      if Gem.loaded_specs['activerecord'].version < Gem::Version.create('7.2')
        belongs_to :partitioned_aggregate,
                   inverse_of: :partitioned_events,
                   primary_key: %w[partition_key aggregate_id],
                   query_constraints: %w[events_partition_key aggregate_id]
      else
        belongs_to :partitioned_aggregate,
                   inverse_of: :partitioned_events,
                   primary_key: %w[partition_key aggregate_id],
                   foreign_key: %w[events_partition_key aggregate_id]
      end
    end
  end
end
