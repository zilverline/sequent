CREATE OR REPLACE PROCEDURE delete_all_snapshots(_now timestamp with time zone DEFAULT NOW())
LANGUAGE plpgsql SET search_path FROM CURRENT AS $$
BEGIN
  UPDATE aggregates_that_need_snapshots
     SET snapshot_outdated_at = _now
   WHERE snapshot_outdated_at IS NULL;
  DELETE FROM snapshot_records;
END;
$$;
