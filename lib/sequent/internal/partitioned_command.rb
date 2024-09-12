# frozen_string_literal: true

require 'active_record'
require_relative '../application_record'

module Sequent
  module Internal
    class PartitionedCommand < Sequent::ApplicationRecord
      self.table_name = :commands

      belongs_to :command_type
      has_many :partitioned_events,
               inverse_of: :partitioned_command
    end
  end
end
