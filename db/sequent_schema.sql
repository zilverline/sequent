DROP TYPE IF EXISTS aggregate_event_type CASCADE;
CREATE TYPE aggregate_event_type AS (
  aggregate_type text,
  aggregate_id uuid,
  events_partition_key text,
  snapshot_threshold integer,
  event_type text,
  event_json jsonb
);

CREATE OR REPLACE FUNCTION load_event(
  _aggregate_id uuid,
  _sequence_number integer
) RETURNS SETOF aggregate_event_type
LANGUAGE plpgsql AS $$
BEGIN
  RETURN QUERY SELECT aggregate_type::text, _aggregate_id, ''::text, snapshot_threshold, event_type::text, event_json::jsonb
                 FROM event_records event JOIN stream_records stream ON event.aggregate_id = stream.aggregate_id
                WHERE stream.aggregate_id = _aggregate_id
                  AND sequence_number = _sequence_number;
END;
$$;

CREATE OR REPLACE FUNCTION load_events(
  _aggregate_ids jsonb,
  _use_snapshots boolean DEFAULT TRUE,
  _until timestamptz DEFAULT NULL
) RETURNS SETOF aggregate_event_type
LANGUAGE plpgsql AS $$
DECLARE
  _aggregate_id event_records.aggregate_id%TYPE;
  _snapshot_event snapshot_records;
  _snapshot_event_sequence_number integer;
  _stream_record stream_records;
BEGIN
  FOR _aggregate_id IN SELECT * FROM jsonb_array_elements_text(_aggregate_ids) LOOP
    SELECT *
      INTO _stream_record
      FROM stream_records
     WHERE stream_records.aggregate_id = _aggregate_id;
    IF NOT FOUND THEN
      CONTINUE;
    END IF;

    _snapshot_event = NULL;
    _snapshot_event_sequence_number = 0;
    IF _use_snapshots THEN
      SELECT * INTO _snapshot_event
        FROM snapshot_records e
       WHERE e.aggregate_id = _aggregate_id
         AND (_until IS NULL OR e.created_at < _until)
       ORDER BY e.sequence_number DESC
       LIMIT 1;
      IF FOUND THEN
        RETURN NEXT (
          _stream_record.aggregate_type::text,
          _stream_record.aggregate_id,
          ''::text,
          _stream_record.snapshot_threshold,
          _snapshot_event.snapshot_type::text,
          _snapshot_event.snapshot_json::jsonb
        );
        _snapshot_event_sequence_number = _snapshot_event.sequence_number;
      END IF;
    END IF;

    RETURN QUERY SELECT _stream_record.aggregate_type::text,
                        _stream_record.aggregate_id,
                        ''::text,
                        _stream_record.snapshot_threshold,
                        e.event_type::text,
                        e.event_json::jsonb
                   FROM event_records e
                  WHERE e.aggregate_id = _aggregate_id
                    AND e.sequence_number >= _snapshot_event_sequence_number
                    AND (_until IS NULL OR e.created_at < _until)
                  ORDER BY e.sequence_number;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION store_command(_command jsonb) RETURNS bigint
LANGUAGE plpgsql AS $$
DECLARE
  _id command_records.id%TYPE;
  _command_without_nulls jsonb = jsonb_strip_nulls(_command->'command_json');
BEGIN
  INSERT INTO command_records (
    created_at, user_id, aggregate_id, command_type, command_json,
    event_aggregate_id, event_sequence_number
  ) VALUES (
    (_command->>'created_at')::timestamp,
    (_command_without_nulls->>'user_id')::uuid,
    (_command_without_nulls->>'aggregate_id')::uuid,
    _command->>'command_type',
    _command->'command_json',
    (_command_without_nulls->>'event_aggregate_id')::uuid,
    (_command_without_nulls->'event_sequence_number')::integer
  ) RETURNING id INTO STRICT _id;
  RETURN _id;
END;
$$;

CREATE OR REPLACE PROCEDURE store_events(_command jsonb, _aggregates_with_events jsonb)
LANGUAGE plpgsql AS $$
DECLARE
  _command_record_id command_records.id%TYPE;
  _aggregate jsonb;
  _aggregate_without_nulls jsonb;
  _events jsonb;
  _event jsonb;
  _aggregate_id stream_records.aggregate_id%TYPE;
  _created_at stream_records.created_at%TYPE;
  _snapshot_threshold stream_records.snapshot_threshold%TYPE;
  _sequence_number event_records.sequence_number%TYPE;
BEGIN
  _command_record_id = store_command(_command);

  FOR _aggregate, _events IN SELECT row->0, row->1 FROM jsonb_array_elements(_aggregates_with_events) AS row LOOP
    _aggregate_id = (_aggregate->>'aggregate_id')::uuid;
    _aggregate_without_nulls = jsonb_strip_nulls(_aggregate);
    _snapshot_threshold = _aggregate_without_nulls->'snapshot_threshold';

    IF NOT EXISTS (SELECT 1 FROM stream_records WHERE aggregate_id = _aggregate_id) THEN
      _created_at = _events->0->>'created_at';
      _sequence_number = _events->0->'event_json'->'sequence_number';
      IF _sequence_number <> 1 THEN
        RAISE EXCEPTION 'sequence number of first event new aggregate must be 1, was %', _sequence_number;
      END IF;

      INSERT INTO stream_records (created_at, aggregate_type, aggregate_id, snapshot_threshold)
           VALUES (_created_at, _aggregate->>'aggregate_type', _aggregate_id, _snapshot_threshold);
    END IF;

    FOR _event IN SELECT * FROM jsonb_array_elements(_events) LOOP
      _created_at = _event->'created_at';
      _sequence_number = _event->'event_json'->'sequence_number';
      INSERT INTO event_records (aggregate_id, sequence_number, created_at, event_type, event_json, command_record_id)
           VALUES (
             (_event->'event_json'->>'aggregate_id')::uuid,
             _sequence_number,
             _created_at,
             _event->>'event_type',
             _event->'event_json',
             _command_record_id
           );
    END LOOP;
  END LOOP;
END;
$$;

CREATE OR REPLACE PROCEDURE store_snapshots(_snapshots jsonb)
LANGUAGE plpgsql AS $$
DECLARE
  _aggregate_id uuid;
  _snapshot jsonb;
BEGIN
  FOR _snapshot IN SELECT * FROM jsonb_array_elements(_snapshots) LOOP
    _aggregate_id = _snapshot->>'aggregate_id';
    INSERT INTO snapshot_records (aggregate_id, sequence_number, created_at, snapshot_type, snapshot_json)
         VALUES (
           _aggregate_id,
           (_snapshot->'sequence_number')::integer,
           (_snapshot->>'created_at')::timestamptz,
           _snapshot->>'snapshot_type',
           _snapshot->'snapshot_json'
         );
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION load_latest_snapshot(_aggregate_id uuid) RETURNS aggregate_event_type
LANGUAGE SQL AS $$
  SELECT a.aggregate_type, a.aggregate_id, '', a.snapshot_threshold, s.snapshot_type, s.snapshot_json::jsonb
    FROM snapshot_records s JOIN stream_records a ON s.aggregate_id = a.aggregate_id
   WHERE s.aggregate_id = _aggregate_id
   ORDER BY sequence_number DESC
   LIMIT 1;
$$;

CREATE OR REPLACE PROCEDURE delete_snapshots_before(_aggregate_id uuid, _sequence_number integer)
LANGUAGE plpgsql AS $$
BEGIN
  DELETE FROM snapshot_records
   WHERE aggregate_id = _aggregate_id
     AND sequence_number < _sequence_number;
END;
$$;

CREATE OR REPLACE FUNCTION aggregates_that_need_snapshots(_last_aggregate_id uuid, _limit integer)
  RETURNS TABLE (aggregate_id uuid)
LANGUAGE plpgsql AS $$
BEGIN
  RETURN QUERY SELECT stream.aggregate_id
    FROM stream_records stream
   WHERE (_last_aggregate_id IS NULL OR stream.aggregate_id > _last_aggregate_id)
     AND snapshot_threshold IS NOT NULL
     AND snapshot_threshold <= (
           (SELECT MAX(events.sequence_number) FROM event_records events WHERE stream.aggregate_id = events.aggregate_id) -
           COALESCE((SELECT MAX(snapshots.sequence_number) FROM snapshot_records snapshots WHERE stream.aggregate_id = snapshots.aggregate_id), 0))
   ORDER BY 1
   LIMIT _limit;
END;
$$;

CREATE OR REPLACE PROCEDURE permanently_delete_commands_without_events(_aggregate_id uuid, _organization_id uuid)
LANGUAGE plpgsql AS $$
BEGIN
  IF _organization_id IS NOT NULL THEN
    RAISE EXCEPTION 'deleting by organization_id is not supported by this version of Sequent';
  END IF;
  IF _aggregate_id IS NULL AND _organization_id IS NULL THEN
    RAISE EXCEPTION 'aggregate_id or organization_id must be specified to delete commands';
  END IF;

  DELETE FROM command_records
   WHERE (_aggregate_id IS NULL OR aggregate_id = _aggregate_id)
     --AND (_organization_id IS NULL OR organization_id = _organization_id)
     AND NOT EXISTS (SELECT 1 FROM event_records WHERE command_record_id = command_records.id);
END;
$$;

CREATE OR REPLACE PROCEDURE permanently_delete_event_streams(_aggregate_ids jsonb)
LANGUAGE plpgsql AS $$
BEGIN
  DELETE FROM event_records
   USING jsonb_array_elements_text(_aggregate_ids) AS ids (id)
   WHERE event_records.aggregate_id = ids.id::uuid;
  DELETE FROM stream_records
   USING jsonb_array_elements_text(_aggregate_ids) AS ids (id)
   WHERE stream_records.aggregate_id = ids.id::uuid;
END;
$$;
