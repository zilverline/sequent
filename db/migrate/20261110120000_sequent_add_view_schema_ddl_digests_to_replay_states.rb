# frozen_string_literal: true

class SequentAddViewSchemaDdlDigestsToReplayStates < ActiveRecord::Migration[7.2]
  def change
    Sequent::Support::Database.with_search_path(Sequent.configuration.event_store_schema_name) do
      add_column :replay_states, :view_schema_ddl_digests, :jsonb
    end
  end
end
