# frozen_string_literal: true

class SequentLoadEventsByPartitionKey < ActiveRecord::Migration[7.2]
  def up
    Sequent::Support::Database.with_search_path(Sequent.configuration.event_store_schema_name) do
      execute_sql_file 'enrich_event_json', version: 2
      execute_sql_file 'enrich_command_json', version: 2
      execute_sql_file 'load_event', version: 3
      execute_sql_file 'load_events', version: 3
      execute_sql_file 'load_latest_snapshots', version: 3
      execute_sql_file 'aggregates_that_need_snapshots', version: 3
    end
  end

  def down
    Sequent::Support::Database.with_search_path(Sequent.configuration.event_store_schema_name) do
      execute_sql_file 'aggregates_that_need_snapshots', version: 2
      execute_sql_file 'load_latest_snapshots', version: 2
      execute_sql_file 'load_events', version: 2
      execute_sql_file 'load_event', version: 2
      execute_sql_file 'enrich_command_json', version: 1
      execute_sql_file 'enrich_event_json', version: 1
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
