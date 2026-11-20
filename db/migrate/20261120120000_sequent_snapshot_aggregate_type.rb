# frozen_string_literal: true

class SequentSnapshotAggregateType < ActiveRecord::Migration[7.2]
  def up
    Sequent::Support::Database.with_search_path(Sequent.configuration.event_store_schema_name) do
      say 'Altering aggregates_that_need_snapshots'
      suppress_messages do
        execute <<~SQL
          ALTER TABLE aggregates_that_need_snapshots ADD COLUMN aggregate_type_id smallint;
          UPDATE aggregates_that_need_snapshots s
             SET aggregate_type_id = a.aggregate_type_id
            FROM aggregates a
           WHERE a.aggregate_id = s.aggregate_id;
          ALTER TABLE aggregates_that_need_snapshots
            ALTER COLUMN aggregate_type_id SET NOT NULL,
            ADD FOREIGN KEY (aggregate_type_id) REFERENCES aggregate_types (id);
        SQL
      end

      execute_sql_file 'store_aggregates', version: 5
      execute_sql_file 'store_snapshots', version: 4
      execute_sql_file 'aggregates_that_need_snapshots', version: 4
      execute_sql_file 'select_aggregates_for_snapshotting', version: 3
    end
  end

  def down
    Sequent::Support::Database.with_search_path(Sequent.configuration.event_store_schema_name) do
      execute_sql_file 'select_aggregates_for_snapshotting', version: 2
      execute_sql_file 'aggregates_that_need_snapshots', version: 3
      execute_sql_file 'store_snapshots', version: 3
      execute_sql_file 'store_aggregates', version: 4

      say 'Reverting aggregates_that_need_snapshots'
      suppress_messages do
        execute 'ALTER TABLE aggregates_that_need_snapshots DROP COLUMN aggregate_type_id'
      end
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
