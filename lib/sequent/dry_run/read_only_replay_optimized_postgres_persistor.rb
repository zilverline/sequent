# frozen_string_literal: true

require_relative '../core/persistors/replay_optimized_postgres_persistor'
module Sequent
  module DryRun
    # Subclass of ReplayOptimizedPostgresPersistor
    # This persistor does not persist anything. Mainly usefull for
    # performance testing migrations.
    class ReadOnlyReplayOptimizedPostgresPersistor < Core::Persistors::ReplayOptimizedPostgresPersistor
      def prepare
        @starting = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def commit
        # Running in dryrun mode, not committing anything.
        ending = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        elapsed = ending - @starting
        count = @record_store.values.sum(&:size)
        Sequent.logger.info(
          "dryrun: processed #{count} records in #{elapsed.round(2)} s (#{(count / elapsed).round(2)} records/s)",
        )
        clear
      end
    end
  end
end
