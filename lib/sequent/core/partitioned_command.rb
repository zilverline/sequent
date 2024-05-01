# frozen_string_literal: true

require 'active_record'
require_relative '../application_record'

module Sequent
  module Core
    class PartitionedCommand < Sequent::ApplicationRecord
      self.table_name = :commands

      belongs_to :command_type
      has_many :events,
               inverse_of: :command,
               class_name: :PartitionedEvent
    end
  end
end
