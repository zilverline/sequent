CREATE OR REPLACE PROCEDURE store_events(_command jsonb, _aggregates_with_events jsonb)
LANGUAGE plpgsql SET search_path FROM CURRENT AS $$
DECLARE
  _command_id commands.id%TYPE;
  _aggregates jsonb;
  _aggregate jsonb;
  _events jsonb;
  _aggregate_id aggregates.aggregate_id%TYPE;
  _events_partition_key aggregates.events_partition_key%TYPE;
  _last_sequence_number events.sequence_number%TYPE;
  _next_sequence_number events.sequence_number%TYPE;
BEGIN
  CALL update_types(_command, _aggregates_with_events);

  _command_id = store_command(_command);

  CALL store_aggregates(_aggregates_with_events);

  FOR _aggregate, _events IN SELECT row->0, row->1 FROM jsonb_array_elements(_aggregates_with_events) AS row
                             ORDER BY row->0->'aggregate_id', row->1->0->'event_json'->'sequence_number'
  LOOP
    _aggregate_id = _aggregate->>'aggregate_id';
    SELECT events_partition_key INTO STRICT _events_partition_key FROM aggregates WHERE aggregate_id = _aggregate_id;

    SELECT sequence_number
      INTO _last_sequence_number
      FROM events
     WHERE partition_key = _events_partition_key
       AND aggregate_id = _aggregate_id
     ORDER BY 1 DESC
     LIMIT 1;

    SELECT MIN(event->'event_json'->>'sequence_number')
      INTO _next_sequence_number
      FROM jsonb_array_elements(_events) AS event;

    -- Check sequence number of first new event to ensure optimistic locking works correctly
    -- (otherwise two concurrent transactions could insert events with different first/next
    -- sequence number and no constraint violation would be raised).
    IF _last_sequence_number IS NULL AND _next_sequence_number <> 1 THEN
      RAISE EXCEPTION 'sequence_number of first event must be 1, but was % (aggregate %)', _next_sequence_number, _aggregate_id
            USING ERRCODE = 'integrity_constraint_violation';
    ELSIF _last_sequence_number IS NOT NULL AND _next_sequence_number > _last_sequence_number + 1 THEN
      RAISE EXCEPTION 'sequence_number must be consecutive, but last sequence number was % and next is % (aggregate %)',
                      _last_sequence_number, _next_sequence_number, _aggregate_id
            USING ERRCODE = 'integrity_constraint_violation';
    END IF;

    INSERT INTO events (partition_key, aggregate_id, sequence_number, created_at, command_id, event_type_id, event_json)
    SELECT _events_partition_key,
           _aggregate_id,
           (event->'event_json'->'sequence_number')::integer,
           (event->>'created_at')::timestamptz,
           _command_id,
           (SELECT id FROM event_types WHERE type = event->>'event_type'),
           (event->'event_json') - '{aggregate_id,created_at,event_type,sequence_number}'::text[]
      FROM jsonb_array_elements(_events) AS event
     ORDER BY 1, 2, 3;
  END LOOP;

  _aggregates = (SELECT jsonb_agg(row->0) FROM jsonb_array_elements(_aggregates_with_events) AS row);
  CALL update_unique_keys(_aggregates);
END;
$$;
