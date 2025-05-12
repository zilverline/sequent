CREATE OR REPLACE PROCEDURE store_aggregates(_aggregates_with_events jsonb)
LANGUAGE plpgsql SET search_path FROM CURRENT AS $$
DECLARE
  _aggregate jsonb;
  _events jsonb;
  _aggregate_id aggregates.aggregate_id%TYPE;
  _events_partition_key aggregates.events_partition_key%TYPE;
  _current_partition_key aggregates.events_partition_key%TYPE;
  _snapshot_outdated_at aggregates_that_need_snapshots.snapshot_outdated_at%TYPE;
BEGIN
  FOR _aggregate, _events IN SELECT row->0, row->1 FROM jsonb_array_elements(_aggregates_with_events) AS row ORDER BY row->0->>'aggregate_id' LOOP
    _aggregate_id = _aggregate->>'aggregate_id';

    _events_partition_key = COALESCE(_aggregate->>'events_partition_key', '');
    INSERT INTO aggregates (aggregate_id, created_at, aggregate_type_id, events_partition_key)
    VALUES (
      _aggregate_id,
      (_events->0->>'created_at')::timestamptz,
      (SELECT id FROM aggregate_types WHERE type = _aggregate->>'aggregate_type'),
      _events_partition_key
    ) ON CONFLICT (aggregate_id) DO NOTHING;

    _current_partition_key = (SELECT events_partition_key FROM aggregates WHERE aggregate_id = _aggregate_id);
    IF _current_partition_key <> _events_partition_key THEN
      INSERT INTO partition_key_changes AS row (aggregate_id, old_partition_key, new_partition_key)
      VALUES (_aggregate_id, _current_partition_key, _events_partition_key)
          ON CONFLICT (aggregate_id)
          DO UPDATE SET new_partition_key = EXCLUDED.new_partition_key,
                        updated_at = NOW()
                  WHERE row.new_partition_key IS DISTINCT FROM EXCLUDED.new_partition_key;
    ELSE
      DELETE FROM partition_key_changes WHERE aggregate_id = _aggregate_id;
    END IF;

    _snapshot_outdated_at = _aggregate->>'snapshot_outdated_at';
    IF _snapshot_outdated_at IS NOT NULL THEN
      INSERT INTO aggregates_that_need_snapshots AS row (aggregate_id, snapshot_outdated_at)
      VALUES (_aggregate_id, _snapshot_outdated_at)
          ON CONFLICT (aggregate_id) DO UPDATE
         SET snapshot_outdated_at = LEAST(row.snapshot_outdated_at, EXCLUDED.snapshot_outdated_at)
       WHERE row.snapshot_outdated_at IS DISTINCT FROM EXCLUDED.snapshot_outdated_at;
    END IF;
  END LOOP;
END;
$$;
