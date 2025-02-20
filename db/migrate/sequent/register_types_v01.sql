CREATE OR REPLACE PROCEDURE register_types(_types jsonb)
LANGUAGE plpgsql SET search_path FROM CURRENT AS $$
BEGIN
  WITH types AS (
    SELECT DISTINCT type
      FROM jsonb_array_elements_text(_types->'command_types') AS type
    EXCEPT
    SELECT type FROM command_types
  )
  INSERT INTO command_types (type)
  SELECT type FROM types
   ORDER BY 1
      ON CONFLICT DO NOTHING;

  WITH types AS (
    SELECT DISTINCT type AS type
      FROM jsonb_array_elements_text(_types->'aggregate_root_types') AS type
    EXCEPT
    SELECT type FROM aggregate_types
  )
  INSERT INTO aggregate_types (type)
  SELECT type FROM types
   ORDER BY 1
      ON CONFLICT DO NOTHING;

  WITH types AS (
    SELECT DISTINCT type AS type
      FROM jsonb_array_elements_text(_types->'event_types') AS type
    EXCEPT
    SELECT type FROM event_types
  )
  INSERT INTO event_types (type)
  SELECT type FROM types
   ORDER BY 1
      ON CONFLICT DO NOTHING;
END;
$$;
