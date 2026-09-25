# frozen_string_literal: true

class SequentIndexAggregateUniqueKeysByScopeAndKey < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def up
    Sequent::Support::Database.with_search_path(Sequent.configuration.event_store_schema_name) do
      # btree_gin provides the GIN operator class for the text scope column.
      execute 'CREATE EXTENSION IF NOT EXISTS btree_gin'
      execute <<~SQL
        CREATE INDEX CONCURRENTLY IF NOT EXISTS aggregate_unique_keys_scope_key_idx
            ON aggregate_unique_keys USING gin (scope, key jsonb_path_ops)
      SQL
    end
  end

  def down
    Sequent::Support::Database.with_search_path(Sequent.configuration.event_store_schema_name) do
      execute 'DROP INDEX CONCURRENTLY IF EXISTS aggregate_unique_keys_scope_key_idx'
    end
  end
end
