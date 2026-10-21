CREATE OR REPLACE FUNCTION load_events(
  _aggregate_ids jsonb,
  _use_snapshots boolean DEFAULT TRUE,
  _until timestamptz DEFAULT NULL,
  _snapshot_version_by_type jsonb DEFAULT '{}'
) RETURNS SETOF aggregate_event_type
-- STABLE runs every statement against the calling query's snapshot, so a partition key change
-- committed between looking up the key and querying the events cannot make the events disappear.
LANGUAGE plpgsql STABLE SET search_path FROM CURRENT AS $$
DECLARE
  _aggregate_id aggregates.aggregate_id%TYPE;
  _aggregate_type aggregate_types.type%TYPE;
  _events_partition_key aggregates.events_partition_key%TYPE;
  _snapshot_sequence_number snapshot_records.sequence_number%TYPE;
  _snapshot_type snapshot_records.snapshot_type%TYPE;
  _snapshot_json snapshot_records.snapshot_json%TYPE;
BEGIN
  FOR _aggregate_id IN SELECT * FROM jsonb_array_elements_text(_aggregate_ids) LOOP
    SELECT aggregate_types.type, aggregates.events_partition_key
      INTO _aggregate_type, _events_partition_key
      FROM aggregates
      JOIN aggregate_types ON aggregate_type_id = aggregate_types.id
     WHERE aggregate_id = _aggregate_id;

    CONTINUE WHEN NOT FOUND;

    _snapshot_sequence_number := 0;
    IF _use_snapshots THEN
      SELECT s.sequence_number, s.snapshot_type, s.snapshot_json
        INTO _snapshot_sequence_number, _snapshot_type, _snapshot_json
        FROM snapshot_records s
       WHERE s.aggregate_id = _aggregate_id
         AND (_until IS NULL OR s.created_at < _until)
         AND s.snapshot_version = COALESCE((_snapshot_version_by_type->_aggregate_type)::integer, 1)
       ORDER BY s.sequence_number DESC
       LIMIT 1;

      IF FOUND THEN
        RETURN NEXT (_aggregate_type, _aggregate_id, _events_partition_key, 0, _snapshot_type, _snapshot_json)::aggregate_event_type;
      ELSE
        _snapshot_sequence_number := 0;
      END IF;
    END IF;

    -- The scalar subquery keeps the events in index order; a join with event_types lets a generic plan
    -- choose a hash join, which then needs a sort.
    RETURN QUERY
    SELECT _aggregate_type, _aggregate_id, _events_partition_key, e.sequence_number,
           (SELECT event_types.type FROM event_types WHERE event_types.id = e.event_type_id),
           enrich_event_json(e)
      FROM events e
     WHERE e.partition_key = _events_partition_key
       AND e.aggregate_id = _aggregate_id
       AND e.sequence_number >= _snapshot_sequence_number
       AND (_until IS NULL OR e.created_at < _until)
     ORDER BY e.sequence_number ASC;
  END LOOP;
END;
$$;
