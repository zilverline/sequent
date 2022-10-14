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
CREATE OR REPLACE FUNCTION load_events(
  _aggregate_ids JSONB,
  _snapshot_event_type event_records.event_type%TYPE,
  _use_snapshots BOOLEAN DEFAULT TRUE,
  _until event_records.created_at%TYPE DEFAULT NULL
) RETURNS SETOF event_records AS
$$
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
                    AND (_until IS NULL OR created_at < _until)
                  ORDER BY sequence_number;
  END LOOP;
END;
$$
LANGUAGE plpgsql;
}

  execute %q{
CREATE OR REPLACE PROCEDURE store_events(_command_record_id command_records.id%TYPE, _streams_with_events JSONB) AS
$$
DECLARE
  _stream JSONB;
  _stream_without_nulls JSONB;
  _events JSONB;
  _event JSONB;
  _aggregate_id stream_records.aggregate_id%TYPE;
  _stream_record_id stream_records.id%TYPE;
  _created_at stream_records.created_at%TYPE;
  _snapshot_threshold stream_records.snapshot_threshold%TYPE;
  _sequence_number event_records.sequence_number%TYPE;
BEGIN
  FOR _stream, _events IN SELECT row->0, row->1 FROM jsonb_array_elements(_streams_with_events) AS row LOOP
    _aggregate_id = _stream->>'aggregate_id';
    _stream_without_nulls = jsonb_strip_nulls(_stream);
    _snapshot_threshold = _stream_without_nulls->'snapshot_threshold';

    SELECT id INTO _stream_record_id FROM stream_records WHERE aggregate_id = _aggregate_id;
    IF NOT FOUND THEN
      _created_at = _events->0->'created_at';
      _sequence_number = _events->0->'sequence_number';
      IF _sequence_number <> 1 THEN
        RAISE EXCEPTION 'sequence number of first event new stream must be 1, was %', _sequence_number;
      END IF;

      INSERT INTO stream_records (created_at, aggregate_type, aggregate_id, snapshot_threshold)
           VALUES (_created_at, _stream->>'aggregate_type', _aggregate_id, _snapshot_threshold)
        RETURNING id
             INTO STRICT _stream_record_id;
    END IF;

    FOR _event IN SELECT * FROM jsonb_array_elements(_events) LOOP
      _created_at = _event->'created_at';
      _sequence_number = _event->'sequence_number';
      INSERT INTO event_records (aggregate_id, sequence_number, created_at, event_type, event_json, command_record_id, stream_record_id)
           VALUES (
             _event->>'aggregate_id',
             _sequence_number,
             _created_at,
             _event->>'event_type',
             _event - 'event_type',
             _command_record_id,
             _stream_record_id
           );
    END LOOP;
  END LOOP;
END;
$$
LANGUAGE plpgsql;
}

  execute %q{
CREATE OR REPLACE FUNCTION aggregates_that_need_snapshots(_last_aggregate_id stream_records.aggregate_id%TYPE, _limit INTEGER, _snapshot_event_type TEXT)
  RETURNS TABLE (aggregate_id stream_records.aggregate_id%TYPE) AS
$$
BEGIN
  RETURN QUERY SELECT stream.aggregate_id
    FROM stream_records stream
   WHERE (_last_aggregate_id IS NULL OR stream.aggregate_id > _last_aggregate_id)
     AND snapshot_threshold IS NOT NULL
     AND snapshot_threshold <= (
           (SELECT MAX(events.sequence_number) FROM event_records events WHERE events.event_type <> _snapshot_event_type AND stream.aggregate_id = events.aggregate_id) -
           COALESCE((SELECT MAX(snapshots.sequence_number) FROM event_records snapshots WHERE snapshots.event_type = _snapshot_event_type AND stream.aggregate_id = snapshots.aggregate_id), 0))
   ORDER BY 1
   LIMIT _limit
     FOR UPDATE;
END;
$$
LANGUAGE plpgsql;
}
end
