# frozen_string_literal: true

class SequentVersionedSnapshots < ActiveRecord::Migration[7.2]
  def up
    Sequent::Support::Database.with_search_path(Sequent.configuration.event_store_schema_name) do
      say 'Altering aggregates_that_need_snapshots'
      suppress_messages do
        execute <<~SQL
          ALTER TABLE aggregates_that_need_snapshots ADD COLUMN snapshot_version integer;
          UPDATE aggregates_that_need_snapshots SET snapshot_version = 1;
          ALTER TABLE aggregates_that_need_snapshots
            ALTER COLUMN snapshot_version SET NOT NULL,
            DROP CONSTRAINT aggregates_that_need_snapshots_pkey CASCADE,
            ADD PRIMARY KEY (aggregate_id, snapshot_version);
        SQL
      end

      say 'Altering snapshot_records'
      suppress_messages do
        execute <<~SQL
          ALTER TABLE snapshot_records ADD COLUMN snapshot_version integer;
          UPDATE snapshot_records SET snapshot_version = 1;
          ALTER TABLE snapshot_records
            ALTER COLUMN snapshot_version SET NOT NULL,
            DROP CONSTRAINT snapshot_records_pkey CASCADE,
            ADD PRIMARY KEY (aggregate_id, snapshot_version, sequence_number),
            ADD FOREIGN KEY (aggregate_id, snapshot_version)
                 REFERENCES aggregates_that_need_snapshots (aggregate_id, snapshot_version)
                         ON DELETE CASCADE ON UPDATE CASCADE;
        SQL
      end

      execute_sql_file 'aggregate_event_type', version: 2
      execute_sql_file 'aggregates_that_need_snapshots', version: 2
      execute_sql_file 'delete_snapshots_before', version: 2
      execute_sql_file 'load_event', version: 2
      execute_sql_file 'load_events', version: 2
      execute_sql_file 'load_latest_snapshots', version: 2
      execute_sql_file 'select_aggregates_for_snapshotting', version: 2
      execute_sql_file 'store_aggregates', version: 3
      execute_sql_file 'store_snapshots', version: 2
    end
  end

  def down
    Sequent::Support::Database.with_search_path(Sequent.configuration.event_store_schema_name) do
      say 'Reverting aggregates_that_need_snapshots'
      suppress_messages do
        execute <<~SQL
          DELETE FROM aggregates_that_need_snapshots WHERE snapshot_version <> 1;
          ALTER TABLE aggregates_that_need_snapshots
            DROP CONSTRAINT aggregates_that_need_snapshots_pkey CASCADE,
            DROP COLUMN snapshot_version,
            ADD PRIMARY KEY (aggregate_id);
        SQL
      end

      say 'Reverting snapshot_records'
      suppress_messages do
        execute <<~SQL
          ALTER TABLE snapshot_records
            DROP CONSTRAINT snapshot_records_pkey CASCADE,
            DROP COLUMN snapshot_version,
            ADD PRIMARY KEY (aggregate_id, sequence_number),
            ADD FOREIGN KEY (aggregate_id)
                 REFERENCES aggregates_that_need_snapshots (aggregate_id)
                         ON DELETE CASCADE ON UPDATE CASCADE;
        SQL
      end

      execute_sql_file 'aggregate_event_type', version: 1
      execute_sql_file 'aggregates_that_need_snapshots', version: 1
      execute_sql_file 'delete_snapshots_before', version: 1
      execute_sql_file 'load_event', version: 1
      execute_sql_file 'load_events', version: 1
      execute_sql_file 'load_latest_snapshots', version: 1
      execute_sql_file 'select_aggregates_for_snapshotting', version: 1
      execute_sql_file 'store_aggregates', version: 2
      execute_sql_file 'store_snapshots', version: 1
    end
  end

  private

  def execute_sql_file(filename, version:)
    say "Applying '#{filename}' version #{version}", true
    suppress_messages do
      execute File.read(
        File.join(
          File.dirname(__FILE__),
          format('sequent/%s_v%02d.sql', filename, version),
        ),
      )
    end
  end
end
