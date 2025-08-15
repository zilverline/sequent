# frozen_string_literal: true

class SequentAddIndexDefinitionsToReplayStates < ActiveRecord::Migration[7.2]
  def change
    Sequent::Support::Database.with_search_path(Sequent.configuration.event_store_schema_name) do
      add_column :replay_states, :index_definitions, :jsonb
      add_column :replay_states, :table_cluster_indexes, :jsonb
      remove_check_constraint :replay_states, name: 'valid_replay_state'
      add_check_constraint :replay_states, <<~SQL, name: 'valid_replay_state'
        state IN ('created', 'prepared', 'initial_replay', 'initial_replay_completed', 'incremental_replay', 'prepare_for_activation', 'ready_for_activation', 'failed', 'done', 'aborted')
      SQL
    end
  end
end
