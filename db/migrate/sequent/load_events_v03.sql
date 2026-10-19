CREATE OR REPLACE FUNCTION load_events(
  _aggregate_ids jsonb,
  _use_snapshots boolean DEFAULT TRUE,
  _until timestamptz DEFAULT NULL,
  _snapshot_version_by_type jsonb DEFAULT '{}'
) RETURNS SETOF aggregate_event_type
LANGUAGE plpgsql SET search_path FROM CURRENT AS $$
DECLARE
  _aggregate_id aggregates.aggregate_id%TYPE;
  _aggregate_type aggregate_types.type%TYPE;
  _events_partition_key aggregates.events_partition_key%TYPE;
BEGIN
  FOR _aggregate_id IN SELECT * FROM jsonb_array_elements_text(_aggregate_ids) LOOP
    -- Changing the events partition key updates a key referenced by the events, which needs a
    -- FOR UPDATE lock on the aggregate. FOR KEY SHARE blocks that change until the events are
    -- loaded, without waiting for transactions that only append events (FOR NO KEY UPDATE).
    SELECT aggregate_types.type, aggregates.events_partition_key
      INTO _aggregate_type, _events_partition_key
      FROM aggregates
      JOIN aggregate_types ON aggregate_type_id = aggregate_types.id
     WHERE aggregate_id = _aggregate_id
       FOR KEY SHARE OF aggregates;

    CONTINUE WHEN NOT FOUND;

    RETURN QUERY WITH
      snapshot AS MATERIALIZED (
        SELECT s.*
          FROM snapshot_records s
         WHERE _use_snapshots
           AND s.aggregate_id = _aggregate_id
           AND (_until IS NULL OR created_at < _until)
           AND snapshot_version = COALESCE((_snapshot_version_by_type->_aggregate_type)::integer, 1)
         ORDER BY s.sequence_number DESC LIMIT 1
      )
    SELECT _aggregate_type, _aggregate_id, _events_partition_key, 0 AS sequence_number, s.snapshot_type, s.snapshot_json
      FROM snapshot s
    UNION ALL
    SELECT _aggregate_type, _aggregate_id, _events_partition_key, e.sequence_number, event_types.type, enrich_event_json(e)
      FROM events e
      JOIN event_types ON e.event_type_id = event_types.id
     WHERE e.partition_key = _events_partition_key
       AND e.aggregate_id = _aggregate_id
       AND e.sequence_number >= COALESCE((SELECT sequence_number FROM snapshot), 0)
       AND (_until IS NULL OR e.created_at < _until)
    ORDER BY sequence_number ASC;
  END LOOP;
END;
$$;
