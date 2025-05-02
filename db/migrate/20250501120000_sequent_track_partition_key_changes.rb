# frozen_string_literal: true

class SequentTrackPartitionKeyChanges < ActiveRecord::Migration[7.2]
  def up
    Sequent::Support::Database.with_search_path(Sequent.configuration.event_store_schema_name) do
      create_table :partition_key_changes, id: false do |t|
        t.uuid :aggregate_id, null: false, primary_key: true
        t.text :old_partition_key, null: false
        t.text :new_partition_key, null: false
        t.timestamptz :created_at, null: false, default: -> { 'now()' }
        t.timestamptz :updated_at, null: false, default: -> { 'now()' }
      end

      add_foreign_key :partition_key_changes,
                      :aggregates,
                      name: :aggregate_fk,
                      primary_key: :aggregate_id,
                      on_delete: :cascade,
                      on_update: :cascade

      execute_sql_file 'store_aggregates', version: 2
    end
  end

  def down
    Sequent::Support::Database.with_search_path(Sequent.configuration.event_store_schema_name) do
      execute_sql_file 'store_aggregates', version: 1
      drop_table :partition_key_changes
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
