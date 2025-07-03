# frozen_string_literal: true

class SequentTrackProjectorsReplayState < ActiveRecord::Migration[7.2]
  def change
    Sequent::Support::Database.with_search_path(Sequent.configuration.event_store_schema_name) do
      create_table :replay_states do |t|
        t.text :state, null: false
        t.text :projectors, array: true, null: false
        t.bigint :continue_replay_at_xact_id, null: true
        t.timestamptz :created_at, precision: 6, null: false, default: -> { 'NOW()' }
        t.timestamptz :updated_at, precision: 6, null: false, default: -> { 'NOW()' }
      end

      add_check_constraint :replay_states, <<~SQL, name: 'valid_replay_state'
        state IN ('created', 'prepared', 'initial_replay', 'incremental_replay', 'ready_for_activation', 'done')
      SQL

      execute <<~SQL
        CREATE UNIQUE INDEX replay_states_active_replay_idx ON replay_states ((TRUE)) WHERE state NOT IN ('done')
      SQL
    end
  end
end
