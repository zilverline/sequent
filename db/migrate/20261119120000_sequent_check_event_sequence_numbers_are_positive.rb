# frozen_string_literal: true

class SequentCheckEventSequenceNumbersArePositive < ActiveRecord::Migration[7.2]
  def up
    Sequent::Support::Database.with_search_path(Sequent.configuration.event_store_schema_name) do
      execute <<~SQL
        ALTER TABLE events ADD CONSTRAINT events_sequence_number_check CHECK (sequence_number > 0) NOT VALID
      SQL
    end
  end

  def down
    Sequent::Support::Database.with_search_path(Sequent.configuration.event_store_schema_name) do
      execute 'ALTER TABLE events DROP CONSTRAINT IF EXISTS events_sequence_number_check'
    end
  end
end
