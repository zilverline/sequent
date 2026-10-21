CREATE OR REPLACE FUNCTION load_event(
  _aggregate_id uuid,
  _sequence_number integer
) RETURNS SETOF aggregate_event_type RETURNS NULL ON NULL INPUT
-- STABLE runs both statements against the calling query's snapshot, like load_events.
LANGUAGE plpgsql STABLE SET search_path FROM CURRENT AS $$
DECLARE
  _aggregate_type aggregate_types.type%TYPE;
  _events_partition_key aggregates.events_partition_key%TYPE;
BEGIN
  SELECT aggregate_types.type, aggregates.events_partition_key
    INTO _aggregate_type, _events_partition_key
    FROM aggregates
    JOIN aggregate_types ON aggregate_type_id = aggregate_types.id
   WHERE aggregate_id = _aggregate_id;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  RETURN QUERY SELECT _aggregate_type, _aggregate_id, _events_partition_key, e.sequence_number, event_types.type, enrich_event_json(e)
    FROM events e
    JOIN event_types ON e.event_type_id = event_types.id
   WHERE e.partition_key = _events_partition_key
     AND e.aggregate_id = _aggregate_id
     AND e.sequence_number = _sequence_number;
END;
$$;
