CREATE OR REPLACE FUNCTION load_latest_snapshot(_aggregate_id uuid) RETURNS aggregate_event_type
LANGUAGE SQL SET search_path FROM CURRENT AS $$
  SELECT (SELECT type FROM aggregate_types WHERE id = a.aggregate_type_id),
         a.aggregate_id,
         a.events_partition_key,
         s.snapshot_type,
         s.snapshot_json
    FROM aggregates a JOIN snapshot_records s ON a.aggregate_id = s.aggregate_id
   WHERE a.aggregate_id = _aggregate_id
   ORDER BY s.sequence_number DESC
   LIMIT 1;
$$;
