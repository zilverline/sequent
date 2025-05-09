DROP PROCEDURE IF EXISTS delete_snapshots_before(_aggregate_id uuid, _sequence_number integer, _now timestamp with time zone);

CREATE OR REPLACE PROCEDURE delete_snapshots_before(
  _aggregate_id uuid,
  _sequence_number integer,
  _now timestamp with time zone DEFAULT NOW(),
  _snapshot_version_by_type jsonb DEFAULT '{}'
)
LANGUAGE plpgsql SET search_path FROM CURRENT AS $$
BEGIN
  DELETE FROM snapshot_records s
   WHERE aggregate_id = _aggregate_id
     AND snapshot_version = COALESCE(
           (SELECT _snapshot_version_by_type->>(type.type)
              FROM aggregates
              JOIN aggregate_types type ON aggregate_type_id = type.id
             WHERE s.aggregate_id = aggregates.aggregate_id)::integer,
           1
         )
     AND sequence_number < _sequence_number;

  UPDATE aggregates_that_need_snapshots a
     SET snapshot_outdated_at = _now
   WHERE aggregate_id = _aggregate_id
     AND snapshot_outdated_at IS NULL
     AND NOT EXISTS (SELECT 1 FROM snapshot_records s WHERE aggregate_id = _aggregate_id AND a.snapshot_version = s.snapshot_version);
END;
$$;
