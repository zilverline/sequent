CREATE OR REPLACE PROCEDURE store_events(_command jsonb, _aggregates_with_events jsonb)
LANGUAGE plpgsql SET search_path FROM CURRENT AS $$
DECLARE
  _command_id commands.id%TYPE;
  _aggregates jsonb;
  _aggregate jsonb;
  _events jsonb;
  _aggregate_id aggregates.aggregate_id%TYPE;
  _events_partition_key aggregates.events_partition_key%TYPE;
BEGIN
  CALL update_types(_command, _aggregates_with_events);

  _command_id = store_command(_command);

  CALL store_aggregates(_aggregates_with_events);

  _aggregates = (SELECT jsonb_agg(row->0) FROM jsonb_array_elements(_aggregates_with_events) AS row);
  CALL update_unique_keys(_aggregates);

  FOR _aggregate, _events IN SELECT row->0, row->1 FROM jsonb_array_elements(_aggregates_with_events) AS row
                             ORDER BY row->0->'aggregate_id', row->1->0->'event_json'->'sequence_number'
  LOOP
    _aggregate_id = _aggregate->>'aggregate_id';
    SELECT events_partition_key INTO STRICT _events_partition_key FROM aggregates WHERE aggregate_id = _aggregate_id;

    INSERT INTO events (partition_key, aggregate_id, sequence_number, created_at, command_id, event_type_id, event_json)
    SELECT _events_partition_key,
           _aggregate_id,
           (event->'event_json'->'sequence_number')::integer,
           (event->>'created_at')::timestamptz,
           _command_id,
           (SELECT id FROM event_types WHERE type = event->>'event_type'),
           (event->'event_json') - '{aggregate_id,created_at,event_type,sequence_number}'::text[]
      FROM jsonb_array_elements(_events) AS event;
  END LOOP;
END;
$$;
