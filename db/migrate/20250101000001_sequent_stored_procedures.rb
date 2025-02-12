# frozen_string_literal: true

class SequentStoredProcedures < ActiveRecord::Migration[7.2]
  def up
    Sequent::Support::Database.with_search_path(Sequent.configuration.event_store_schema_name) do
      execute_sql_file 'aggregate_event_type', version: 1
      execute_sql_file 'enrich_command_json', version: 1
      execute_sql_file 'aggregates_that_need_snapshots', version: 1
      execute_sql_file 'command_records', version: 1
      execute_sql_file 'delete_all_snapshots', version: 1
      execute_sql_file 'delete_snapshots_before', version: 1
      execute_sql_file 'enrich_event_json', version: 1
      execute_sql_file 'event_records', version: 1
      execute_sql_file 'load_event', version: 1
      execute_sql_file 'load_events', version: 1
      execute_sql_file 'load_latest_snapshots', version: 1
      execute_sql_file 'permanently_delete_commands_without_events', version: 1
      execute_sql_file 'permanently_delete_event_streams', version: 1
      execute_sql_file 'save_events_trigger', version: 1
      execute_sql_file 'select_aggregates_for_snapshotting', version: 1
      execute_sql_file 'store_aggregates', version: 1
      execute_sql_file 'store_command', version: 1
      execute_sql_file 'store_events', version: 1
      execute_sql_file 'store_snapshots', version: 1
      execute_sql_file 'stream_records', version: 1
      execute_sql_file 'update_types', version: 1
      execute_sql_file 'update_unique_keys', version: 1
    end
  end

  def down
    fail ActiveRecord::IrreversibleMigration
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
