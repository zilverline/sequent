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
            PartitionKeyChange.connection.exec_update("SET LOCAL statement_timeout TO '30s'", 'statement_timeout')

            # New style projector replay
            # Ensure no new version can be inserted or updated while we update partition keys.
            connection.execute("LOCK TABLE #{Sequent::Migrations::ReplayState.quoted_table_name} IN ROW EXCLUSIVE MODE")
            if Sequent::Migrations::ReplayState.replaying.present?
              fail Sequent::Migrations::ConcurrentMigration,
                   'cannot update partition keys while projectors are replaying'
            end

            # Old style view schema migrations
            if Sequent.migrations_class.present?
              # Ensure no new version can be inserted or updated while we update partition keys.
              connection.execute("LOCK TABLE #{Sequent::Migrations::Versions.quoted_table_name} IN ROW EXCLUSIVE MODE")

              if Sequent::Migrations::Versions.running.present?
                fail Sequent::Migrations::ConcurrentMigration,
                     'cannot update partition keys while view schema migration is running'
              end
            end

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
