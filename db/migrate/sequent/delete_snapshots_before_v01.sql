CREATE OR REPLACE PROCEDURE delete_snapshots_before(_aggregate_id uuid, _sequence_number integer, _now timestamp with time zone DEFAULT NOW())
LANGUAGE plpgsql SET search_path FROM CURRENT AS $$
BEGIN
  DELETE FROM snapshot_records
   WHERE aggregate_id = _aggregate_id
     AND sequence_number < _sequence_number;

  UPDATE aggregates_that_need_snapshots
     SET snapshot_outdated_at = _now
   WHERE aggregate_id = _aggregate_id
     AND snapshot_outdated_at IS NULL
     AND NOT EXISTS (SELECT 1 FROM snapshot_records WHERE aggregate_id = _aggregate_id);
END;
$$;
