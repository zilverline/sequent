CREATE OR REPLACE FUNCTION load_events(
  _aggregate_ids jsonb,
  _use_snapshots boolean DEFAULT TRUE,
  _until timestamptz DEFAULT NULL
) RETURNS SETOF aggregate_event_type
LANGUAGE plpgsql SET search_path FROM CURRENT AS $$
DECLARE
  _aggregate_id aggregates.aggregate_id%TYPE;
BEGIN
  FOR _aggregate_id IN SELECT * FROM jsonb_array_elements_text(_aggregate_ids) LOOP
    -- Use a single query to avoid race condition with UPDATEs to the events partition key
    -- in case transaction isolation level is lower than repeatable read (the default of
    -- PostgreSQL is read committed).
    RETURN QUERY WITH
      aggregate AS (
        SELECT aggregate_types.type, aggregate_id, events_partition_key
          FROM aggregates
          JOIN aggregate_types ON aggregate_type_id = aggregate_types.id
         WHERE aggregate_id = _aggregate_id
      ),
      snapshot AS (
        SELECT *
          FROM snapshot_records
         WHERE _use_snapshots
           AND aggregate_id = _aggregate_id
           AND (_until IS NULL OR created_at < _until)
         ORDER BY sequence_number DESC LIMIT 1
      )
    (SELECT a.*, s.snapshot_type, s.snapshot_json FROM aggregate a, snapshot s)
    UNION ALL
    (SELECT a.*, event_types.type, enrich_event_json(e)
       FROM aggregate a
       JOIN events e ON (a.events_partition_key, a.aggregate_id) = (e.partition_key, e.aggregate_id)
       JOIN event_types ON e.event_type_id = event_types.id
      WHERE e.sequence_number >= COALESCE((SELECT sequence_number FROM snapshot), 0)
        AND (_until IS NULL OR e.created_at < _until)
      ORDER BY e.sequence_number ASC);
  END LOOP;
END;
$$;
