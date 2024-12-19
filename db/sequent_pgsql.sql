DROP TYPE IF EXISTS aggregate_event_type CASCADE;
CREATE TYPE aggregate_event_type AS (
  aggregate_type text,
  aggregate_id uuid,
  events_partition_key text,
  event_type text,
  event_json jsonb
);

CREATE OR REPLACE FUNCTION enrich_command_json(command commands) RETURNS jsonb
LANGUAGE plpgsql AS $$
BEGIN
  RETURN jsonb_build_object(
      'command_type', (SELECT type FROM command_types WHERE command_types.id = command.command_type_id),
      'created_at', command.created_at,
      'user_id', command.user_id,
      'aggregate_id', command.aggregate_id,
      'event_aggregate_id', command.event_aggregate_id,
      'event_sequence_number', command.event_sequence_number
    )
    || command.command_json;
END
$$;

CREATE OR REPLACE FUNCTION enrich_event_json(event events) RETURNS jsonb
LANGUAGE plpgsql AS $$
BEGIN
  RETURN jsonb_build_object(
      'aggregate_id', event.aggregate_id,
      'sequence_number', event.sequence_number,
      'created_at', event.created_at
    )
    || event.event_json;
END
$$;

CREATE OR REPLACE FUNCTION load_event(
  _aggregate_id uuid,
  _sequence_number integer
) RETURNS SETOF aggregate_event_type
LANGUAGE plpgsql AS $$
BEGIN
  RETURN QUERY SELECT aggregate_types.type,
         a.aggregate_id,
         a.events_partition_key,
         event_types.type,
         enrich_event_json(e)
    FROM aggregates a
        INNER JOIN events e ON (a.events_partition_key, a.aggregate_id) = (e.partition_key, e.aggregate_id)
        INNER JOIN aggregate_types ON a.aggregate_type_id = aggregate_types.id
        INNER JOIN event_types ON e.event_type_id = event_types.id
   WHERE a.aggregate_id = _aggregate_id
     AND e.sequence_number = _sequence_number;
END;
$$;

CREATE OR REPLACE FUNCTION load_events(
  _aggregate_ids jsonb,
  _use_snapshots boolean DEFAULT TRUE,
  _until timestamptz DEFAULT NULL
) RETURNS SETOF aggregate_event_type
LANGUAGE plpgsql AS $$
DECLARE
  _aggregate_id aggregates.aggregate_id%TYPE;
BEGIN
  FOR _aggregate_id IN SELECT * FROM jsonb_array_elements_text(_aggregate_ids) LOOP
    -- Use a single query to avoid race condition with UPDATEs to the events partition key
    -- in case transaction isolation level is lower than repeatable read (the default of
    -- PostgreSQL is read committed).
    RETURN QUERY WITH
      aggregate AS (
        SELECT aggregate_types.type, aggregate_id, events_partition_key
          FROM aggregates
          JOIN aggregate_types ON aggregate_type_id = aggregate_types.id
         WHERE aggregate_id = _aggregate_id
      ),
      snapshot AS (
        SELECT *
          FROM snapshot_records
         WHERE _use_snapshots
           AND aggregate_id = _aggregate_id
           AND (_until IS NULL OR created_at < _until)
         ORDER BY sequence_number DESC LIMIT 1
      )
    (SELECT a.*, s.snapshot_type, s.snapshot_json FROM aggregate a, snapshot s)
    UNION ALL
    (SELECT a.*, event_types.type, enrich_event_json(e)
       FROM aggregate a
       JOIN events e ON (a.events_partition_key, a.aggregate_id) = (e.partition_key, e.aggregate_id)
       JOIN event_types ON e.event_type_id = event_types.id
      WHERE e.sequence_number >= COALESCE((SELECT sequence_number FROM snapshot), 0)
        AND (_until IS NULL OR e.created_at < _until)
      ORDER BY e.sequence_number ASC);
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION store_command(_command jsonb) RETURNS bigint
LANGUAGE plpgsql AS $$
DECLARE
  _id commands.id%TYPE;
  _command_json jsonb = _command->'command_json';
BEGIN
  IF NOT EXISTS (SELECT 1 FROM command_types t WHERE t.type = _command->>'command_type') THEN
    -- Only when new types are added is this path executed, which should be rare. We do not use a sequence here To avoid
    -- wasting ids (which are limited for this table) on rollback, we lock the table and select the minimum next id.
    LOCK TABLE command_types IN ACCESS EXCLUSIVE MODE;
    INSERT INTO command_types (id, type)
    VALUES ((SELECT COALESCE(MAX(id) + 1, 1) FROM command_types), _command->>'command_type')
        ON CONFLICT (type) DO NOTHING;
  END IF;

  INSERT INTO commands (
    created_at, user_id, aggregate_id, command_type_id, command_json,
    event_aggregate_id, event_sequence_number
  ) VALUES (
    (_command->>'created_at')::timestamptz,
    (_command_json->>'user_id')::uuid,
    (_command_json->>'aggregate_id')::uuid,
    (SELECT id FROM command_types WHERE type = _command->>'command_type'),
    (_command->'command_json') - '{command_type,created_at,organization_id,user_id,aggregate_id,event_aggregate_id,event_sequence_number}'::text[],
    (_command_json->>'event_aggregate_id')::uuid,
    NULLIF(_command_json->'event_sequence_number', 'null'::jsonb)::integer
  ) RETURNING id INTO STRICT _id;
  RETURN _id;
END;
$$;

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
  _type TEXT;
BEGIN
  _command_id = store_command(_command);

  FOR _type IN (
    SELECT DISTINCT row->0->>'aggregate_type' AS type
      FROM jsonb_array_elements(_aggregates_with_events) AS row
    EXCEPT
    SELECT type FROM aggregate_types
    ORDER BY 1
  ) LOOP
    -- Only when new types are added is this path executed, which should be rare. We do not use a sequence here To avoid
    -- wasting ids (which are limited for this table) on rollback, we lock the table and select the minimum next id.
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
    -- Only when new types are added is this path executed, which should be rare. We do not use a sequence here To avoid
    -- wasting ids (which are limited for this table) on rollback, we lock the table and select the minimum next id.
    LOCK TABLE event_types IN ACCESS EXCLUSIVE MODE;
    INSERT INTO event_types (id, type) VALUES ((SELECT COALESCE(MAX(id) + 1, 1) FROM event_types), _type)
        ON CONFLICT (type) DO NOTHING;
  END LOOP;

  FOR _aggregate, _events IN SELECT row->0, row->1 FROM jsonb_array_elements(_aggregates_with_events) AS row
                             ORDER BY row->0->'aggregate_id', row->1->0->'event_json'->'sequence_number'
  LOOP
    _aggregate_id = _aggregate->>'aggregate_id';
    _provided_events_partition_key = _aggregate->>'events_partition_key';
    _snapshot_outdated_at = _aggregate->>'snapshot_outdated_at';

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

CREATE OR REPLACE PROCEDURE store_snapshots(_snapshots jsonb)
LANGUAGE plpgsql AS $$
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

CREATE OR REPLACE FUNCTION load_latest_snapshot(_aggregate_id uuid) RETURNS aggregate_event_type
LANGUAGE SQL AS $$
  SELECT (SELECT type FROM aggregate_types WHERE id = a.aggregate_type_id),
         a.aggregate_id,
         a.events_partition_key,
         s.snapshot_type,
         s.snapshot_json
    FROM aggregates a JOIN snapshot_records s ON a.aggregate_id = s.aggregate_id
   WHERE a.aggregate_id = _aggregate_id
   ORDER BY s.sequence_number DESC
   LIMIT 1;
$$;

CREATE OR REPLACE PROCEDURE delete_all_snapshots(_now timestamp with time zone DEFAULT NOW())
LANGUAGE plpgsql AS $$
BEGIN
  UPDATE aggregates_that_need_snapshots
     SET snapshot_outdated_at = _now
   WHERE snapshot_outdated_at IS NULL;
  DELETE FROM snapshot_records;
END;
$$;

CREATE OR REPLACE PROCEDURE delete_snapshots_before(_aggregate_id uuid, _sequence_number integer, _now timestamp with time zone DEFAULT NOW())
LANGUAGE plpgsql AS $$
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

CREATE OR REPLACE FUNCTION aggregates_that_need_snapshots(_last_aggregate_id uuid, _limit integer)
  RETURNS TABLE (aggregate_id uuid)
LANGUAGE plpgsql AS $$
BEGIN
  RETURN QUERY SELECT a.aggregate_id
    FROM aggregates_that_need_snapshots a
   WHERE a.snapshot_outdated_at IS NOT NULL
     AND (_last_aggregate_id IS NULL OR a.aggregate_id > _last_aggregate_id)
   ORDER BY 1
   LIMIT _limit;
END;
$$;

CREATE OR REPLACE FUNCTION select_aggregates_for_snapshotting(_limit integer, _reschedule_snapshot_scheduled_before timestamp with time zone, _now timestamp with time zone DEFAULT NOW())
  RETURNS TABLE (aggregate_id uuid)
LANGUAGE plpgsql AS $$
BEGIN
  RETURN QUERY WITH scheduled AS MATERIALIZED (
    SELECT a.aggregate_id
      FROM aggregates_that_need_snapshots AS a
     WHERE snapshot_outdated_at IS NOT NULL
     ORDER BY snapshot_outdated_at ASC, snapshot_sequence_number_high_water_mark DESC, aggregate_id ASC
     LIMIT _limit
       FOR UPDATE
   ) UPDATE aggregates_that_need_snapshots AS row
        SET snapshot_scheduled_at = _now
       FROM scheduled
      WHERE row.aggregate_id = scheduled.aggregate_id
        AND (row.snapshot_scheduled_at IS NULL OR row.snapshot_scheduled_at < _reschedule_snapshot_scheduled_before)
    RETURNING row.aggregate_id;
END;
$$;

CREATE OR REPLACE PROCEDURE permanently_delete_commands_without_events(_aggregate_id uuid, _organization_id uuid)
LANGUAGE plpgsql AS $$
BEGIN
  IF _aggregate_id IS NULL AND _organization_id IS NULL THEN
    RAISE EXCEPTION 'aggregate_id or organization_id must be specified to delete commands';
  END IF;

  DELETE FROM commands
   WHERE (_aggregate_id IS NULL OR aggregate_id = _aggregate_id)
     AND NOT EXISTS (SELECT 1 FROM events WHERE command_id = commands.id);
END;
$$;

CREATE OR REPLACE PROCEDURE permanently_delete_event_streams(_aggregate_ids jsonb)
LANGUAGE plpgsql AS $$
BEGIN
  DELETE FROM events
   USING jsonb_array_elements_text(_aggregate_ids) AS ids (id)
    JOIN aggregates ON ids.id::uuid = aggregates.aggregate_id
   WHERE events.partition_key = aggregates.events_partition_key
     AND events.aggregate_id = aggregates.aggregate_id;
  DELETE FROM aggregates
   USING jsonb_array_elements_text(_aggregate_ids) AS ids (id)
   WHERE aggregates.aggregate_id = ids.id::uuid;
END;
$$;

DROP VIEW IF EXISTS command_records;
CREATE VIEW command_records (id, user_id, aggregate_id, command_type, command_json, created_at, event_aggregate_id, event_sequence_number) AS
  SELECT id,
         user_id,
         aggregate_id,
         (SELECT type FROM command_types WHERE command_types.id = command.command_type_id),
         enrich_command_json(command),
         created_at,
         event_aggregate_id,
         event_sequence_number
    FROM commands command;

DROP VIEW IF EXISTS event_records;
CREATE VIEW event_records (aggregate_id, partition_key, sequence_number, created_at, event_type, event_json, command_record_id, xact_id) AS
     SELECT aggregate.aggregate_id,
            event.partition_key,
            event.sequence_number,
            event.created_at,
            type.type,
            enrich_event_json(event) AS event_json,
            command_id,
            event.xact_id
       FROM events event
       JOIN aggregates aggregate ON aggregate.aggregate_id = event.aggregate_id AND aggregate.events_partition_key = event.partition_key
       JOIN event_types type ON event.event_type_id = type.id;

DROP VIEW IF EXISTS stream_records;
CREATE VIEW stream_records (aggregate_id, events_partition_key, aggregate_type, created_at) AS
     SELECT aggregates.aggregate_id,
            aggregates.events_partition_key,
            aggregate_types.type,
            aggregates.created_at
       FROM aggregates JOIN aggregate_types ON aggregates.aggregate_type_id = aggregate_types.id;

CREATE OR REPLACE FUNCTION save_events_on_delete_trigger() RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO saved_event_records (operation, timestamp, "user", aggregate_id, partition_key, sequence_number, created_at, event_type, event_json, command_id, xact_id)
  SELECT 'D',
         statement_timestamp(),
         user,
         o.aggregate_id,
         o.partition_key,
         o.sequence_number,
         o.created_at,
         (SELECT type FROM event_types WHERE event_types.id = o.event_type_id),
         o.event_json,
         o.command_id,
         o.xact_id
    FROM old_table o;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION save_events_on_update_trigger() RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO saved_event_records (operation, timestamp, "user", aggregate_id, partition_key, sequence_number, created_at, event_type, event_json, command_id, xact_id)
  SELECT 'U',
         statement_timestamp(),
         user,
         o.aggregate_id,
         o.partition_key,
         o.sequence_number,
         o.created_at,
         (SELECT type FROM event_types WHERE event_types.id = o.event_type_id),
         o.event_json,
         o.command_id,
         o.xact_id
    FROM old_table o LEFT JOIN new_table n ON o.aggregate_id = n.aggregate_id AND o.sequence_number = n.sequence_number
   WHERE n IS NULL
      -- Only save when event related information changes
      OR o.created_at <> n.created_at
      OR o.event_type_id <> n.event_type_id
      OR o.event_json <> n.event_json;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER save_events_on_delete_trigger
    AFTER DELETE ON events
    REFERENCING OLD TABLE AS old_table
    FOR EACH STATEMENT EXECUTE FUNCTION save_events_on_delete_trigger();
CREATE OR REPLACE TRIGGER save_events_on_update_trigger
    AFTER UPDATE ON events
    REFERENCING OLD TABLE AS old_table NEW TABLE AS new_table
    FOR EACH STATEMENT EXECUTE FUNCTION save_events_on_update_trigger();
