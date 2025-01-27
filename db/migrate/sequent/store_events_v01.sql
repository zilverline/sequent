CREATE OR REPLACE PROCEDURE store_events(_command jsonb, _aggregates_with_events jsonb)
LANGUAGE plpgsql AS $$
DECLARE
  _command_id commands.id%TYPE;
  _aggregate jsonb;
  _events jsonb;
  _aggregate_id aggregates.aggregate_id%TYPE;
  _aggregate_row aggregates%ROWTYPE;
  _provided_events_partition_key aggregates.events_partition_key%TYPE;
  _events_partition_key aggregates.events_partition_key%TYPE;
  _snapshot_outdated_at aggregates_that_need_snapshots.snapshot_outdated_at%TYPE;
  _unique_keys jsonb;
BEGIN
  CALL update_types(_command, _aggregates_with_events);

  _command_id = store_command(_command);

  FOR _aggregate IN SELECT row->0 FROM jsonb_array_elements(_aggregates_with_events) AS row LOOP
    _aggregate_id = _aggregate->>'aggregate_id';
    _unique_keys = COALESCE(_aggregate->'unique_keys', '{}'::jsonb);

    DELETE FROM aggregate_unique_keys AS target
     WHERE target.aggregate_id = _aggregate_id
       AND NOT (_unique_keys ? target.scope);
  END LOOP;

  FOR _aggregate, _events IN SELECT row->0, row->1 FROM jsonb_array_elements(_aggregates_with_events) AS row
                             ORDER BY row->0->'aggregate_id', row->1->0->'event_json'->'sequence_number'
  LOOP
    _aggregate_id = _aggregate->>'aggregate_id';
    _provided_events_partition_key = _aggregate->>'events_partition_key';
    _snapshot_outdated_at = _aggregate->>'snapshot_outdated_at';
    _unique_keys = COALESCE(_aggregate->'unique_keys', '{}'::jsonb);

    SELECT * INTO _aggregate_row FROM aggregates WHERE aggregate_id = _aggregate_id;
    _events_partition_key = COALESCE(_provided_events_partition_key, _aggregate_row.events_partition_key, '');

    INSERT INTO aggregates (aggregate_id, created_at, aggregate_type_id, events_partition_key)
    VALUES (
      _aggregate_id,
      (_events->0->>'created_at')::timestamptz,
      (SELECT id FROM aggregate_types WHERE type = _aggregate->>'aggregate_type'),
      _events_partition_key
    ) ON CONFLICT (aggregate_id)
      DO UPDATE SET events_partition_key = EXCLUDED.events_partition_key
              WHERE aggregates.events_partition_key IS DISTINCT FROM EXCLUDED.events_partition_key;

    BEGIN
      INSERT INTO aggregate_unique_keys AS target (aggregate_id, scope, key)
      SELECT _aggregate_id, key, value
        FROM jsonb_each(_unique_keys) AS x
          ON CONFLICT (aggregate_id, scope) DO UPDATE
         SET key = EXCLUDED.key
       WHERE target.key <> EXCLUDED.key;
    EXCEPTION
      WHEN unique_violation THEN
        RAISE unique_violation
        USING MESSAGE = 'duplicate unique key value for aggregate ' || (_aggregate->>'aggregate_type') || ' ' || _aggregate_id || ' (' || SQLERRM || ')';
    END;

    INSERT INTO events (partition_key, aggregate_id, sequence_number, created_at, command_id, event_type_id, event_json)
    SELECT _events_partition_key,
           _aggregate_id,
           (event->'event_json'->'sequence_number')::integer,
           (event->>'created_at')::timestamptz,
           _command_id,
           (SELECT id FROM event_types WHERE type = event->>'event_type'),
           (event->'event_json') - '{aggregate_id,created_at,event_type,sequence_number}'::text[]
      FROM jsonb_array_elements(_events) AS event;

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
