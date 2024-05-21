# frozen_string_literal: true

ActiveRecord::Schema.define do
  create_table 'snapshot_records', primary_key: %w[aggregate_id sequence_number], force: true do |t|
    t.uuid 'aggregate_id', null: false
    t.integer 'sequence_number', null: false
    t.datetime 'created_at', null: false
    t.text 'snapshot_type', null: false
    t.jsonb 'snapshot_json', null: false
  end

  schema = File.read("#{File.dirname(__FILE__)}/sequent_schema.sql")
  execute schema
end
