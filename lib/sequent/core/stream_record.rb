require 'active_record'

module Sequent
  module Core
    class StreamRecord < ActiveRecord::Base

      self.table_name = "stream_records"

      validates_presence_of :aggregate_type, :aggregate_id
      validates_numericality_of :snapshot_threshold, :only_integer => true, :greater_than => 0, :allow_nil => true

      has_many :events
    end
  end
end
