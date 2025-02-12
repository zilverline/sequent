CREATE OR REPLACE FUNCTION aggregates_that_need_snapshots(_last_aggregate_id uuid, _limit integer)
  RETURNS TABLE (aggregate_id uuid)
LANGUAGE plpgsql SET search_path FROM CURRENT AS $$
BEGIN
  RETURN QUERY SELECT a.aggregate_id
    FROM aggregates_that_need_snapshots a
   WHERE a.snapshot_outdated_at IS NOT NULL
     AND (_last_aggregate_id IS NULL OR a.aggregate_id > _last_aggregate_id)
   ORDER BY 1
   LIMIT _limit;
END;
$$;
