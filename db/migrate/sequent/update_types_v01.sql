CREATE OR REPLACE PROCEDURE update_types(_command jsonb, _aggregates_with_events jsonb)
LANGUAGE plpgsql SET search_path FROM CURRENT AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM command_types t WHERE t.type = _command->>'command_type') THEN
    -- Only try inserting if it doesn't exist to avoid exhausting the id sequence
    INSERT INTO command_types (type)
    VALUES (_command->>'command_type')
     ON CONFLICT DO NOTHING;
  END IF;

  WITH types AS (
    SELECT DISTINCT row->0->>'aggregate_type' AS type
      FROM jsonb_array_elements(_aggregates_with_events) AS row
  )
  INSERT INTO aggregate_types (type)
  SELECT type FROM types
   WHERE type NOT IN (SELECT type FROM aggregate_types)
   ORDER BY 1
      ON CONFLICT DO NOTHING;

  WITH types AS (
    SELECT DISTINCT events->>'event_type' AS type
      FROM jsonb_array_elements(_aggregates_with_events) AS row
           CROSS JOIN LATERAL jsonb_array_elements(row->1) AS events
  )
  INSERT INTO event_types (type)
  SELECT type FROM types
   WHERE type NOT IN (SELECT type FROM event_types)
   ORDER BY 1
      ON CONFLICT DO NOTHING;
END;
$$;
