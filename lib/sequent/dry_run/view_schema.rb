# frozen_string_literal: true

require_relative '../migrations/view_schema'
require_relative 'read_only_replay_optimized_postgres_persistor'

module Sequent
  module DryRun
    # Subclass of Migrations::ViewSchema to dry run a migration.
    # This migration does not insert anything into the database, mainly usefull
    # for performance testing migrations.
    class ViewSchema < Migrations::ViewSchema
      def migrate_dryrun(regex:)
        persistor = DryRun::ReadOnlyReplayOptimizedPostgresPersistor.new

        projectors = Sequent::Core::Migratable.all.select { |p| p.replay_persistor.nil? && p.name.match(regex || /.*/) }
        if projectors.present?
          Sequent.logger.info "Dry run using the following projectors: #{projectors.map(&:name).join(', ')}"

          starting = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          replay!(persistor, projectors:)
          ending = Process.clock_gettime(Process::CLOCK_MONOTONIC)

          Sequent.logger.info("Done migrate_dryrun for version #{Sequent.new_version} in #{ending - starting} s")
        end
      end

      private

      # override so no ids are inserted.
      def insert_ids
        ->(progress, done, ids) {}
      end
    end
  end
end
