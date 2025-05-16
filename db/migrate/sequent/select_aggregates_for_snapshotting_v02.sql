DROP FUNCTION IF EXISTS select_aggregates_for_snapshotting(_limit integer, _reschedule_snapshot_scheduled_before timestamp with time zone, _now timestamp with time zone);

CREATE OR REPLACE FUNCTION select_aggregates_for_snapshotting(
  _limit integer,
  _reschedule_snapshot_scheduled_before timestamp with time zone,
  _now timestamp with time zone DEFAULT NOW(),
  _snapshot_version_by_type jsonb DEFAULT '{}'
)
  RETURNS SETOF aggregates_that_need_snapshots
LANGUAGE plpgsql SET search_path FROM CURRENT AS $$
BEGIN
  RETURN QUERY WITH scheduled AS MATERIALIZED (
    SELECT s.aggregate_id, s.snapshot_version
      FROM aggregates_that_need_snapshots AS s
     WHERE snapshot_outdated_at IS NOT NULL
       AND snapshot_version = COALESCE(
             (SELECT _snapshot_version_by_type->>(type.type)
                FROM aggregates
                JOIN aggregate_types type ON aggregate_type_id = type.id
               WHERE s.aggregate_id = aggregates.aggregate_id)::integer,
             1
           )
     ORDER BY snapshot_outdated_at ASC, snapshot_sequence_number_high_water_mark DESC, aggregate_id ASC
     LIMIT _limit
       FOR UPDATE
   ), updated AS MATERIALIZED (
     UPDATE aggregates_that_need_snapshots AS row
        SET snapshot_scheduled_at = _now
       FROM scheduled
      WHERE row.aggregate_id = scheduled.aggregate_id
        AND row.snapshot_version = scheduled.snapshot_version
        AND (row.snapshot_scheduled_at IS NULL OR row.snapshot_scheduled_at < _reschedule_snapshot_scheduled_before)
     RETURNING row.*
   )
   SELECT *
     FROM updated
    ORDER BY snapshot_outdated_at ASC, snapshot_sequence_number_high_water_mark DESC, aggregate_id ASC;
END;
$$;
