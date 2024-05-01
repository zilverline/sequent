# frozen_string_literal: true

require 'active_record'
require_relative '../application_record'

module Sequent
  module Internal
    class PartitionedEvent < Sequent::ApplicationRecord
      self.table_name = :events
      self.primary_key = %i[partition_key aggregate_id sequence_number]

      belongs_to :event_type
      belongs_to :command,
                 inverse_of: :events,
                 class_name: :PartitionedCommand
      belongs_to :aggregate,
                 inverse_of: :events,
                 class_name: :PartitionedAggregate
    end
  end
end
