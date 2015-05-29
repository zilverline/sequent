module Sequent
  module Core
    class SnapshotCommand <  Sequent::Core::BaseCommand
      attrs limit: Integer
    end

    class AggregateSnapshotter < BaseCommandHandler

      def handles_message?(message)
        message.is_a? SnapshotCommand
      end

      ##
      # Take up to `limit` snapshots when needed. Throws `:done` when done.
      #
      on SnapshotCommand do |command|
        aggregate_ids = repository.event_store.aggregates_that_need_snapshots(@last_aggregate_id, command.limit)
        aggregate_ids.each do |aggregate_id|
          take_snapshot!(aggregate_id)
        end
        @last_aggregate_id = aggregate_ids.last
        throw :done if @last_aggregate_id.nil?
      end

      def take_snapshot!(aggregate_id)
        aggregate = @repository.load_aggregate(aggregate_id)
        Sequent.logger.info "Taking snapshot for aggregate #{aggregate}"
        aggregate.take_snapshot!
      rescue => e
        Sequent.logger.warn "Failed to take snapshot for aggregate #{aggregate_id}: #{e}", e.inspect
      end
    end
  end
end
