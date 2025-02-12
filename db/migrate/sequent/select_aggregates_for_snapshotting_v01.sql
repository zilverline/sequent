CREATE OR REPLACE FUNCTION select_aggregates_for_snapshotting(_limit integer, _reschedule_snapshot_scheduled_before timestamp with time zone, _now timestamp with time zone DEFAULT NOW())
  RETURNS TABLE (aggregate_id uuid)
LANGUAGE plpgsql SET search_path FROM CURRENT AS $$
BEGIN
  RETURN QUERY WITH scheduled AS MATERIALIZED (
    SELECT a.aggregate_id
      FROM aggregates_that_need_snapshots AS a
     WHERE snapshot_outdated_at IS NOT NULL
     ORDER BY snapshot_outdated_at ASC, snapshot_sequence_number_high_water_mark DESC, aggregate_id ASC
     LIMIT _limit
       FOR UPDATE
   ) UPDATE aggregates_that_need_snapshots AS row
        SET snapshot_scheduled_at = _now
       FROM scheduled
      WHERE row.aggregate_id = scheduled.aggregate_id
        AND (row.snapshot_scheduled_at IS NULL OR row.snapshot_scheduled_at < _reschedule_snapshot_scheduled_before)
    RETURNING row.aggregate_id;
END;
$$;
