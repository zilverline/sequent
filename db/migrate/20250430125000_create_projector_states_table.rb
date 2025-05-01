# frozen_string_literal: true

class CreateProjectorStatesTable < ActiveRecord::Migration[7.2]
  def change
    Sequent::Support::Database.with_search_path(Sequent.configuration.event_store_schema_name) do
      create_table :projector_states, id: false, primary_key: :name do |t|
        t.primary_key :name, :text, null: false
        t.integer :active_version
        t.integer :activating_version
        t.integer :replaying_version
        t.timestamptz :created_at, precision: 6, null: false, default: -> { 'NOW()' }
        t.timestamptz :updated_at, precision: 6, null: false, default: -> { 'NOW()' }
      end

      add_check_constraint :projector_states,
                           'replaying_version IS NULL OR activating_version IS NULL',
                           name: 'replaying_conflicts_with_activating'
      add_check_constraint :projector_states,
                           'replaying_version > active_version',
                           name: 'replaying_newer_then_active'
      add_check_constraint :projector_states,
                           'activating_version > active_version',
                           name: 'activating_newer_than_active'
    end
  end
end
