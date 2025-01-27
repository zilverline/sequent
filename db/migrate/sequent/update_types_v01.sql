CREATE OR REPLACE PROCEDURE update_types(_command jsonb, _aggregates_with_events jsonb)
LANGUAGE plpgsql AS $$
DECLARE
  _type TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM command_types t WHERE t.type = _command->>'command_type') THEN
    -- Only when new types are added is this path executed, which should be rare. We do not use a sequence here to avoid
    -- wasting ids (which are limited for this table) on rollback, we lock the table and select the minimum next id.
    LOCK TABLE command_types IN ACCESS EXCLUSIVE MODE;
    INSERT INTO command_types (id, type)
    VALUES ((SELECT COALESCE(MAX(id) + 1, 1) FROM command_types), _command->>'command_type')
        ON CONFLICT (type) DO NOTHING;
  END IF;

  FOR _type IN (
    SELECT DISTINCT row->0->>'aggregate_type' AS type
      FROM jsonb_array_elements(_aggregates_with_events) AS row
    EXCEPT
    SELECT type FROM aggregate_types
    ORDER BY 1
  ) LOOP
    -- Only when new types are added is this path executed, which should be rare. We do not use a sequence here to avoid
    -- wasting ids (which are limited for this table) on rollback, we lock the table and select the minimum next id.
    LOCK TABLE command_types IN ACCESS EXCLUSIVE MODE;
    LOCK TABLE aggregate_types IN ACCESS EXCLUSIVE MODE;
    INSERT INTO aggregate_types (id, type) VALUES ((SELECT COALESCE(MAX(id) + 1, 1) FROM aggregate_types), _type)
        ON CONFLICT (type) DO NOTHING;
  END LOOP;

  FOR _type IN (
    SELECT DISTINCT events->>'event_type' AS type
      FROM jsonb_array_elements(_aggregates_with_events) AS row
           CROSS JOIN LATERAL jsonb_array_elements(row->1) AS events
    EXCEPT
    SELECT type FROM event_types
    ORDER BY 1
  ) LOOP
    -- Only when new types are added is this path executed, which should be rare. We do not use a sequence here to avoid
    -- wasting ids (which are limited for this table) on rollback, we lock the table and select the minimum next id.
    LOCK TABLE command_types IN ACCESS EXCLUSIVE MODE;
    LOCK TABLE aggregate_types IN ACCESS EXCLUSIVE MODE;
    LOCK TABLE event_types IN ACCESS EXCLUSIVE MODE;
    INSERT INTO event_types (id, type) VALUES ((SELECT COALESCE(MAX(id) + 1, 1) FROM event_types), _type)
        ON CONFLICT (type) DO NOTHING;
  END LOOP;
END;
$$;
