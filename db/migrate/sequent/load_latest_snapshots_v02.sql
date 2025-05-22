DROP FUNCTION IF EXISTS load_latest_snapshot(_aggregate_id uuid);

CREATE OR REPLACE FUNCTION load_latest_snapshot(_aggregate_id uuid, _snapshot_version_by_type jsonb DEFAULT '{}')
RETURNS aggregate_event_type
LANGUAGE SQL SET search_path FROM CURRENT AS $$
  SELECT t.type,
         a.aggregate_id,
         a.events_partition_key,
         0 AS sequence_number,
         s.snapshot_type,
         s.snapshot_json
    FROM aggregates a
    JOIN aggregate_types t on a.aggregate_type_id = t.id
    JOIN snapshot_records s ON a.aggregate_id = s.aggregate_id
   WHERE a.aggregate_id = _aggregate_id
     AND s.snapshot_version = COALESCE((_snapshot_version_by_type->>(t.type))::integer, 1)
   ORDER BY s.sequence_number DESC
   LIMIT 1;
$$;
