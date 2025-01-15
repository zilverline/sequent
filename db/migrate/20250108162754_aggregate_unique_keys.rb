# frozen_string_literal: true

class AggregateUniqueKeys < ActiveRecord::Migration[7.2]
  def up
    say 'Setting up search path', true
    suppress_messages do
      execute <<~SQL
        SELECT set_config('tmp.search_path', current_setting('search_path'), true);
        SELECT set_config('search_path', '#{Sequent.configuration.event_store_schema_name}', true);
      SQL
    end

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

    say 'Restoring search path', true
    suppress_messages do
      execute "SELECT set_config('search_path', current_setting('tmp.search_path'), true)"
    end
  end

  def down
    fail ActiveRecord::IrreversibleMigration
  end
end
