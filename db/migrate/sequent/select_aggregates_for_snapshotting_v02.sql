DROP FUNCTION IF EXISTS select_aggregates_for_snapshotting(_limit integer, _reschedule_snapshot_scheduled_before timestamp with time zone, _now timestamp with time zone);

CREATE OR REPLACE FUNCTION select_aggregates_for_snapshotting(
  _limit integer,
  _reschedule_snapshot_scheduled_before timestamp with time zone,
  _now timestamp with time zone DEFAULT NOW(),
  _snapshot_version_by_type jsonb DEFAULT '{}'
)
  RETURNS TABLE (aggregate_id uuid, aggregate_type text, snapshot_version integer)
LANGUAGE plpgsql SET search_path FROM CURRENT AS $$
BEGIN
  RETURN QUERY WITH scheduled AS MATERIALIZED (
    SELECT s.*, t.type AS aggregate_type
      FROM aggregates_that_need_snapshots AS s
      JOIN aggregates a ON s.aggregate_id = a.aggregate_id
      JOIN aggregate_types t ON a.aggregate_type_id = t.id
     WHERE s.snapshot_outdated_at IS NOT NULL
       AND s.snapshot_version = COALESCE((_snapshot_version_by_type->>(t.type))::integer, 1)
     ORDER BY s.snapshot_outdated_at ASC, s.snapshot_sequence_number_high_water_mark DESC, s.aggregate_id ASC
     LIMIT _limit
       FOR UPDATE OF s SKIP LOCKED
   ), updated AS MATERIALIZED (
     UPDATE aggregates_that_need_snapshots AS row
        SET snapshot_scheduled_at = _now
       FROM scheduled
      WHERE row.aggregate_id = scheduled.aggregate_id
        AND row.snapshot_version = scheduled.snapshot_version
        AND (row.snapshot_scheduled_at IS NULL OR row.snapshot_scheduled_at < _reschedule_snapshot_scheduled_before)
     RETURNING scheduled.*
   )
   SELECT updated.aggregate_id, updated.aggregate_type, updated.snapshot_version
     FROM updated
    ORDER BY snapshot_outdated_at ASC, snapshot_sequence_number_high_water_mark DESC, aggregate_id ASC;
END;
$$;
