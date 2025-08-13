# frozen_string_literal: true

require_relative '../support/database'

module Sequent
  module Migrations
    class Versions < Sequent::ApplicationRecord
      MIGRATE_ONLINE_RUNNING = 1
      MIGRATE_ONLINE_FINISHED = 2
      MIGRATE_OFFLINE_RUNNING = 3
      DONE = nil

      def self.migration_sql
        <<~SQL.chomp
          CREATE TABLE IF NOT EXISTS #{table_name} (version integer NOT NULL, target_projectors text[] DEFAULT '{}'::text[], target_records text[] DEFAULT '{}'::text[], CONSTRAINT version_pk PRIMARY KEY(version));
          ALTER TABLE #{table_name} ADD COLUMN IF NOT EXISTS target_projectors text[] DEFAULT '{}'::text[];
          ALTER TABLE #{table_name} ADD COLUMN IF NOT EXISTS target_records text[] DEFAULT '{}'::text[];
          ALTER TABLE #{table_name} drop constraint if exists only_one_running;
          ALTER TABLE #{table_name} ADD COLUMN IF NOT EXISTS status INTEGER DEFAULT NULL CONSTRAINT only_one_running CHECK (status in (1,2,3));
          ALTER TABLE #{table_name} ADD COLUMN IF NOT EXISTS xmin_xact_id BIGINT;
          DROP INDEX IF EXISTS single_migration_running;
          CREATE UNIQUE INDEX single_migration_running ON #{table_name} ((status * 0)) where status is not null;
        SQL
      end

      scope :done, -> { where(status: DONE) }
      scope :running,
            -> {
              where(status: [MIGRATE_ONLINE_RUNNING, MIGRATE_ONLINE_FINISHED, MIGRATE_OFFLINE_RUNNING])
            }
      scope :later_versions, -> { where('version > ?', Sequent.new_version) }
      scope :migrate_offline_running, -> { where(status: MIGRATE_OFFLINE_RUNNING) }
      scope :migrate_offline_running_or_done, -> { migrate_offline_running.or(done) }

      def self.current_version
        done.latest_version || 0
      end

      def self.version_currently_migrating
        running.latest_version
      end

      def self.latest_version
        latest&.version
      end

      def self.latest
        order('version desc').limit(1).first
      end

      def self.start_online!(new_version)
        create!(
          version: new_version,
          status: MIGRATE_ONLINE_RUNNING,
          xmin_xact_id: Sequent::Support::Database.current_snapshot_xmin_xact_id,
        )
      rescue ActiveRecord::RecordNotUnique
        raise ConcurrentMigration, "Migration for version #{new_version} is already running"
      end

      def self.end_online!(new_version)
        find_by!(version: new_version, status: MIGRATE_ONLINE_RUNNING).update(status: MIGRATE_ONLINE_FINISHED)
      end

      def self.rollback!(new_version)
        running.where(version: new_version).delete_all
      end

      def self.start_offline!(new_version, target_projectors: [], target_records: [])
        current_migration = find_by(version: new_version)
        fail MigrationNotStarted if current_migration.blank?

        current_migration.with_lock('FOR UPDATE NOWAIT') do
          fail MigrationDone if current_migration.status.nil?
          fail ConcurrentMigration if current_migration.status != MIGRATE_ONLINE_FINISHED

          current_migration.update(
            status: MIGRATE_OFFLINE_RUNNING,
            target_projectors:,
            target_records:,
          )
        end
      rescue ActiveRecord::LockWaitTimeout
        raise ConcurrentMigration
      end

      def self.end_offline!(new_version)
        find_by!(version: new_version, status: MIGRATE_OFFLINE_RUNNING).update(status: DONE)
      end
    end
  end
end
