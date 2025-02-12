CREATE OR REPLACE FUNCTION load_event(
  _aggregate_id uuid,
  _sequence_number integer
) RETURNS SETOF aggregate_event_type RETURNS NULL ON NULL INPUT
LANGUAGE plpgsql SET search_path FROM CURRENT AS $$
BEGIN
  RETURN QUERY SELECT aggregate_types.type,
         a.aggregate_id,
         a.events_partition_key,
         event_types.type,
         enrich_event_json(e)
    FROM aggregates a
        INNER JOIN events e ON (a.events_partition_key, a.aggregate_id) = (e.partition_key, e.aggregate_id)
        INNER JOIN aggregate_types ON a.aggregate_type_id = aggregate_types.id
        INNER JOIN event_types ON e.event_type_id = event_types.id
   WHERE a.aggregate_id = _aggregate_id
     AND e.sequence_number = _sequence_number;
END;
$$;
