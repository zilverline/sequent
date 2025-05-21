# frozen_string_literal: true

require 'active_record'
require_relative '../application_record'
require_relative '../migrations/versions'

module Sequent
  module Internal
    class PartitionKeyChange < Sequent::ApplicationRecord
      self.primary_key = %i[aggregate_id]

      belongs_to :partitioned_aggregate, primary_key: :aggregate_id, foreign_key: :aggregate_id

      def self.update_aggregate_partition_keys(limit:)
        count = 0
        limit.times do
          ActiveRecord::Base.transaction do
            if Sequent::Migrations::Versions.running.present?
              fail Sequent::Migrations::ConcurrentMigration,
                   'cannot update partition keys while view schema migration is running'
            end

            PartitionKeyChange.connection.exec_update("SET LOCAL statement_timeout TO '30s'", 'statement_timeout')

            change = PartitionKeyChange.lock('FOR UPDATE SKIP LOCKED').first
            return count unless change

            count += 1

            PartitionedAggregate
              .where(aggregate_id: change.aggregate_id)
              .where('events_partition_key <> ?', change.new_partition_key)
              .update_all(events_partition_key: change.new_partition_key)

            change.destroy!
          end
        end
        count
      end
    end
  end
end
