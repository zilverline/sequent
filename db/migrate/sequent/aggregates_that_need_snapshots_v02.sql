DROP FUNCTION IF EXISTS aggregates_that_need_snapshots(_last_aggregate_id uuid, _limit integer);

CREATE OR REPLACE FUNCTION aggregates_that_need_snapshots(_last_aggregate_id uuid, _limit integer, _snapshot_version_by_type jsonb DEFAULT '{}')
  RETURNS TABLE (aggregate_id uuid)
LANGUAGE plpgsql SET search_path FROM CURRENT AS $$
BEGIN
  RETURN QUERY SELECT a.aggregate_id
    FROM aggregates_that_need_snapshots s
    JOIN aggregates a ON s.aggregate_id = a.aggregate_id
    JOIN aggregate_types type ON a.aggregate_type_id = type.id
   WHERE s.snapshot_outdated_at IS NOT NULL
     AND s.snapshot_version = COALESCE((_snapshot_version_by_type->>(type.type))::integer, 1)
     AND (_last_aggregate_id IS NULL OR s.aggregate_id > _last_aggregate_id)
   ORDER BY 1
   LIMIT _limit;
END;
$$;
