# frozen_string_literal: true

class AggregateUniqueKeys < ActiveRecord::Migration[7.2]
  def up
    Sequent::Support::Database.with_search_path(Sequent.configuration.event_store_schema_name) do
      say 'Creating aggregate_unique_keys table', true
      suppress_messages do
        execute <<~SQL
          CREATE TABLE IF NOT EXISTS aggregate_unique_keys (
              aggregate_id uuid NOT NULL,
              scope text NOT NULL,
              key jsonb NOT NULL,
              PRIMARY KEY (aggregate_id, scope),
              UNIQUE (scope, key),
              FOREIGN KEY (aggregate_id) REFERENCES aggregates (aggregate_id) ON UPDATE CASCADE ON DELETE CASCADE
          )
        SQL
      end

      say 'Creating event store stored procedures and views', true
      suppress_messages do
        sequent_pgsql_filename = File.join(Sequent.configuration.database_schema_directory, 'sequent_pgsql.sql')
        execute File.read(sequent_pgsql_filename)
      end
    end
  end

  def down
    fail ActiveRecord::IrreversibleMigration
  end
end
