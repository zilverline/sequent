ActiveRecord::Schema.define do

  create_table "event_records", :force => true do |t|
    t.uuid "aggregate_id", :null => false
    t.integer "sequence_number", :null => false
    t.datetime "created_at", :null => false
    t.string "event_type", :null => false
    t.text "event_json", :null => false
    t.integer "command_record_id", :null => false
    t.integer "stream_record_id", :null => false
    t.bigint "xact_id"
  end

  execute %Q{
ALTER TABLE event_records ALTER COLUMN xact_id SET DEFAULT pg_current_xact_id()::text::bigint
}
  execute %Q{
CREATE UNIQUE INDEX unique_event_per_aggregate ON event_records (
  aggregate_id,
  sequence_number,
  (CASE event_type WHEN 'Sequent::Core::SnapshotEvent' THEN 0 ELSE 1 END)
)
}
  execute %Q{
CREATE INDEX snapshot_events ON event_records (aggregate_id, sequence_number DESC) WHERE event_type = 'Sequent::Core::SnapshotEvent'
}

  add_index "event_records", ["command_record_id"], :name => "index_event_records_on_command_record_id"
  add_index "event_records", ["event_type"], :name => "index_event_records_on_event_type"
  add_index "event_records", ["created_at"], :name => "index_event_records_on_created_at"
  add_index "event_records", ["xact_id"], :name => "index_event_records_on_xact_id"

  create_table "command_records", :force => true do |t|
    t.string "user_id"
    t.uuid "aggregate_id"
    t.string "command_type", :null => false
    t.string "event_aggregate_id"
    t.integer "event_sequence_number"
    t.text "command_json", :null => false
    t.datetime "created_at", :null => false
  end

  add_index "command_records", ["event_aggregate_id", 'event_sequence_number'], :name => "index_command_records_on_event"

  create_table "stream_records", :force => true do |t|
    t.datetime "created_at", :null => false
    t.string "aggregate_type", :null => false
    t.uuid "aggregate_id", :null => false
    t.integer "snapshot_threshold"
  end

  add_index "stream_records", ["aggregate_id"], :name => "index_stream_records_on_aggregate_id", :unique => true
  execute %q{
ALTER TABLE event_records ADD CONSTRAINT command_fkey FOREIGN KEY (command_record_id) REFERENCES command_records (id)
}
  execute %q{
ALTER TABLE event_records ADD CONSTRAINT stream_fkey FOREIGN KEY (stream_record_id) REFERENCES stream_records (id)
}

  execute %q{
CREATE OR REPLACE FUNCTION load_events(_aggregate_ids JSONB, _snapshot_event_type event_records.event_type%TYPE, _use_snapshots BOOLEAN DEFAULT TRUE) RETURNS SETOF event_records AS $$
DECLARE
  _aggregate_id event_records.aggregate_id%TYPE;
  _snapshot_event event_records;
  _snapshot_event_sequence_number INTEGER;
BEGIN
  FOR _aggregate_id IN SELECT * FROM jsonb_array_elements_text(_aggregate_ids) LOOP
    _snapshot_event = NULL;
    _snapshot_event_sequence_number = 0;
    IF _use_snapshots THEN
      SELECT * INTO _snapshot_event
        FROM event_records
       WHERE aggregate_id = _aggregate_id
         AND event_type = _snapshot_event_type
       ORDER BY sequence_number DESC
       LIMIT 1;
      IF FOUND THEN
        RETURN NEXT _snapshot_event;
        _snapshot_event_sequence_number = _snapshot_event.sequence_number;
      END IF;
    END IF;

    RETURN QUERY SELECT *
                   FROM event_records
                  WHERE aggregate_id = _aggregate_id
                    AND sequence_number >= _snapshot_event_sequence_number
                    AND event_type <> _snapshot_event_type
                  ORDER BY sequence_number;
  END LOOP;
END;
$$
LANGUAGE plpgsql;
}
end
