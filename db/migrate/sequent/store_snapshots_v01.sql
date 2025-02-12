CREATE OR REPLACE PROCEDURE store_snapshots(_snapshots jsonb)
LANGUAGE plpgsql SET search_path FROM CURRENT AS $$
DECLARE
  _aggregate_id uuid;
  _snapshot jsonb;
  _sequence_number snapshot_records.sequence_number%TYPE;
BEGIN
  FOR _snapshot IN SELECT * FROM jsonb_array_elements(_snapshots) LOOP
    _aggregate_id = _snapshot->>'aggregate_id';
    _sequence_number = _snapshot->'sequence_number';

    INSERT INTO aggregates_that_need_snapshots AS row (aggregate_id, snapshot_sequence_number_high_water_mark)
    VALUES (_aggregate_id, _sequence_number)
        ON CONFLICT (aggregate_id) DO UPDATE
       SET snapshot_sequence_number_high_water_mark =
             GREATEST(row.snapshot_sequence_number_high_water_mark, EXCLUDED.snapshot_sequence_number_high_water_mark),
           snapshot_outdated_at = NULL,
           snapshot_scheduled_at = NULL;

    INSERT INTO snapshot_records (aggregate_id, sequence_number, created_at, snapshot_type, snapshot_json)
    VALUES (
      _aggregate_id,
      _sequence_number,
      (_snapshot->>'created_at')::timestamptz,
      _snapshot->>'snapshot_type',
      _snapshot->'snapshot_json'
    );
  END LOOP;
END;
$$;
