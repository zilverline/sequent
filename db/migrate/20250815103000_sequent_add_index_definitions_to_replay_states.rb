# frozen_string_literal: true

class SequentAddIndexDefinitionsToReplayStates < ActiveRecord::Migration[7.2]
  def change
    Sequent::Support::Database.with_search_path(Sequent.configuration.event_store_schema_name) do
      add_column :replay_states, :index_definitions, :jsonb
      add_column :replay_states, :table_cluster_indexes, :jsonb
      remove_check_constraint :replay_states, name: 'valid_replay_state'
      add_check_constraint :replay_states, <<~SQL, name: 'valid_replay_state'
        state IN ('created', 'prepared_initial', 'replaying_initial', 'replaying_increment', 'replayed', 'prepared_completion', 'completed', 'failed', 'aborted')
      SQL
      remove_check_constraint :projector_states, name: 'replaying_newer_then_active'
      remove_check_constraint :projector_states, name: 'activating_newer_than_active'

      execute <<~SQL
        DROP INDEX replay_states_active_replay_idx
      SQL
      execute <<~SQL
        CREATE UNIQUE INDEX replay_states_active_replay_idx ON replay_states ((TRUE)) WHERE state NOT IN ('completed', 'aborted')
      SQL
    end
  end
end
