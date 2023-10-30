# frozen_string_literal: true

module Sequent
  module Core
    ##
    # Take up to `limit` snapshots when needed. Throws `:done` when done.
    #
    class SnapshotCommand < Sequent::Core::BaseCommand
      attrs limit: Integer
    end

    ##
    # Take snapshot of given aggregate
    class TakeSnapshot < Sequent::Core::Command
    end

    class AggregateSnapshotter < BaseCommandHandler
      # By default skip autoregistering this CommandHandler.
      # The AggregateSnapshotter is only autoregistered if autoregistration is enabled.
      self.skip_autoregister = true

      on SnapshotCommand do |command|
        aggregate_ids = Sequent.configuration.event_store.aggregates_that_need_snapshots(
          @last_aggregate_id,
          command.limit,
        )
        aggregate_ids.each do |aggregate_id|
          take_snapshot!(aggregate_id)
        end
        @last_aggregate_id = aggregate_ids.last
        throw :done if @last_aggregate_id.nil?
      end

      on TakeSnapshot do |command|
        take_snapshot!(command.aggregate_id)
      end

      def take_snapshot!(aggregate_id)
        aggregate = repository.load_aggregate(aggregate_id)
        Sequent.logger.info "Taking snapshot for aggregate #{aggregate}"
        aggregate.take_snapshot!
      rescue StandardError => e
        Sequent.logger.error("Failed to take snapshot for aggregate #{aggregate_id}: #{e}, #{e.inspect}")
      end
    end
  end
end
