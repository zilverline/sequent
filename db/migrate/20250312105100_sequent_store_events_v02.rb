# frozen_string_literal: true

class SequentStoreEventsV02 < ActiveRecord::Migration[7.2]
  def up
    Sequent::Support::Database.with_search_path(Sequent.configuration.event_store_schema_name) do
      execute_sql_file 'store_events', version: 2
    end
  end

  def down
    Sequent::Support::Database.with_search_path(Sequent.configuration.event_store_schema_name) do
      execute_sql_file 'store_events', version: 1
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
