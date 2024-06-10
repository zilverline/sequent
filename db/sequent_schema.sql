DROP TYPE IF EXISTS aggregate_event_type CASCADE;
CREATE TYPE aggregate_event_type AS (
  aggregate_type text,
  aggregate_id uuid,
  events_partition_key text,
  snapshot_threshold integer,
  event_type text,
  event_json jsonb
);

CREATE TABLE command_types (id SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, type text UNIQUE NOT NULL);
CREATE TABLE aggregate_types (id SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, type text UNIQUE NOT NULL);
CREATE TABLE event_types (id SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, type text UNIQUE NOT NULL);

CREATE TABLE commands (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    created_at timestamp with time zone NOT NULL,
    user_id uuid,
    aggregate_id uuid,
    command_type_id SMALLINT NOT NULL REFERENCES command_types (id),
    command_json jsonb NOT NULL,
    event_aggregate_id uuid,
    event_sequence_number integer
) PARTITION BY RANGE (id);
CREATE INDEX commands_command_type_id_idx ON commands (command_type_id);
CREATE INDEX commands_aggregate_id_idx ON commands (aggregate_id);
CREATE INDEX commands_event_idx ON commands (event_aggregate_id, event_sequence_number);

CREATE TABLE commands_default PARTITION OF commands DEFAULT;

CREATE TABLE aggregates (
    aggregate_id uuid PRIMARY KEY,
    events_partition_key text NOT NULL DEFAULT '',
    aggregate_type_id SMALLINT NOT NULL REFERENCES aggregate_types (id),
    snapshot_threshold integer,
    created_at timestamp with time zone NOT NULL DEFAULT NOW(),
    UNIQUE (events_partition_key, aggregate_id)
) PARTITION BY RANGE (aggregate_id);
CREATE INDEX aggregates_aggregate_type_id_idx ON aggregates (aggregate_type_id);

CREATE TABLE aggregates_0 PARTITION OF aggregates FOR VALUES FROM (MINVALUE) TO ('40000000-0000-0000-0000-000000000000');
ALTER TABLE aggregates_0 CLUSTER ON aggregates_0_events_partition_key_aggregate_id_key;
CREATE TABLE aggregates_4 PARTITION OF aggregates FOR VALUES FROM ('40000000-0000-0000-0000-000000000000') TO ('80000000-0000-0000-0000-000000000000');
ALTER TABLE aggregates_4 CLUSTER ON aggregates_4_events_partition_key_aggregate_id_key;
CREATE TABLE aggregates_8 PARTITION OF aggregates FOR VALUES FROM ('80000000-0000-0000-0000-000000000000') TO ('c0000000-0000-0000-0000-000000000000');
ALTER TABLE aggregates_8 CLUSTER ON aggregates_8_events_partition_key_aggregate_id_key;
CREATE TABLE aggregates_c PARTITION OF aggregates FOR VALUES FROM ('c0000000-0000-0000-0000-000000000000') TO (MAXVALUE);
ALTER TABLE aggregates_c CLUSTER ON aggregates_c_events_partition_key_aggregate_id_key;

CREATE TABLE events (
  aggregate_id uuid NOT NULL,
  partition_key text DEFAULT '',
  sequence_number integer NOT NULL,
  created_at timestamp with time zone NOT NULL,
  command_id bigint NOT NULL,
  event_type_id SMALLINT NOT NULL REFERENCES event_types (id),
  event_json jsonb NOT NULL,
  xact_id bigint DEFAULT pg_current_xact_id()::text::bigint,
  PRIMARY KEY (partition_key, aggregate_id, sequence_number),
  FOREIGN KEY (partition_key, aggregate_id)
    REFERENCES aggregates (events_partition_key, aggregate_id)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  FOREIGN KEY (command_id) REFERENCES commands (id)
) PARTITION BY RANGE (partition_key);
CREATE INDEX events_command_id_idx ON events (command_id);
CREATE INDEX events_event_type_id_idx ON events (event_type_id);
CREATE INDEX events_xact_id_idx ON events (xact_id) WHERE xact_id IS NOT NULL;

CREATE TABLE events_default PARTITION OF events DEFAULT;
ALTER TABLE events_default CLUSTER ON events_default_pkey;
CREATE TABLE events_2023_and_earlier PARTITION OF events FOR VALUES FROM ('Y00') TO ('Y24');
ALTER TABLE events_2023_and_earlier CLUSTER ON events_2023_and_earlier_pkey;
CREATE TABLE events_2024 PARTITION OF events FOR VALUES FROM ('Y24') TO ('Y25');
ALTER TABLE events_2024 CLUSTER ON events_2024_pkey;
CREATE TABLE events_2025_and_later PARTITION OF events FOR VALUES FROM ('Y25') TO ('Y99');
ALTER TABLE events_2025_and_later CLUSTER ON events_2025_and_later_pkey;
CREATE TABLE events_aggregate PARTITION OF events FOR VALUES FROM ('A') TO ('Ag');
ALTER TABLE events_aggregate CLUSTER ON events_aggregate_pkey;

TRUNCATE TABLE snapshot_records;
ALTER TABLE snapshot_records
  ADD CONSTRAINT aggregate_fkey FOREIGN KEY (aggregate_id) REFERENCES aggregates (aggregate_id)
    ON UPDATE CASCADE ON DELETE CASCADE;

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
         a.snapshot_threshold,
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
        SELECT aggregate_types.type, aggregate_id, events_partition_key, snapshot_threshold
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
    -- Only try inserting if it doesn't exist to avoid exhausting the id sequence
    INSERT INTO command_types (type)
    VALUES (_command->>'command_type')
     ON CONFLICT DO NOTHING;
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
  _provided_events_partition_key aggregates.events_partition_key%TYPE;
  _existing_events_partition_key aggregates.events_partition_key%TYPE;
  _events_partition_key aggregates.events_partition_key%TYPE;
  _snapshot_threshold aggregates.snapshot_threshold%TYPE;
BEGIN
  _command_id = store_command(_command);

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

  FOR _aggregate, _events IN SELECT row->0, row->1 FROM jsonb_array_elements(_aggregates_with_events) AS row
                             ORDER BY row->0->'aggregate_id', row->1->0->'event_json'->'sequence_number'
  LOOP
    _aggregate_id = _aggregate->>'aggregate_id';
    _snapshot_threshold = NULLIF(_aggregate->'snapshot_threshold', 'null'::jsonb);
    _provided_events_partition_key = _aggregate->>'events_partition_key';

    SELECT events_partition_key INTO _existing_events_partition_key FROM aggregates WHERE aggregate_id = _aggregate_id FOR UPDATE;
    _events_partition_key = COALESCE(_provided_events_partition_key, _existing_events_partition_key, '');

    INSERT INTO aggregates (aggregate_id, created_at, aggregate_type_id, events_partition_key, snapshot_threshold)
    VALUES (
      _aggregate_id,
      (_events->0->>'created_at')::timestamptz,
      (SELECT id FROM aggregate_types WHERE type = _aggregate->>'aggregate_type'),
      _events_partition_key,
      _snapshot_threshold
    ) ON CONFLICT (aggregate_id)
      DO UPDATE SET events_partition_key = EXCLUDED.events_partition_key,
                    snapshot_threshold = EXCLUDED.snapshot_threshold
              WHERE aggregates.events_partition_key IS DISTINCT FROM EXCLUDED.events_partition_key
                 OR aggregates.snapshot_threshold IS DISTINCT FROM EXCLUDED.snapshot_threshold;

    INSERT INTO events (partition_key, aggregate_id, sequence_number, created_at, command_id, event_type_id, event_json)
    SELECT _events_partition_key,
           _aggregate_id,
           (event->'event_json'->'sequence_number')::integer,
           (event->>'created_at')::timestamptz,
           _command_id,
           (SELECT id FROM event_types WHERE type = event->>'event_type'),
           (event->'event_json') - '{aggregate_id,created_at,event_type,sequence_number}'::text[]
      FROM jsonb_array_elements(_events) AS event;
  END LOOP;
END;
$$;

CREATE OR REPLACE PROCEDURE store_snapshots(_snapshots jsonb)
LANGUAGE plpgsql AS $$
DECLARE
  _aggregate_id uuid;
  _events_partition_key text;
  _snapshot jsonb;
BEGIN
  FOR _snapshot IN SELECT * FROM jsonb_array_elements(_snapshots) LOOP
    _aggregate_id = _snapshot->>'aggregate_id';

    INSERT INTO snapshot_records (aggregate_id, sequence_number, created_at, snapshot_type, snapshot_json)
         VALUES (
           _aggregate_id,
           (_snapshot->'sequence_number')::integer,
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
         a.snapshot_threshold,
         s.snapshot_type,
         s.snapshot_json
    FROM aggregates a JOIN snapshot_records s ON a.aggregate_id = s.aggregate_id
   WHERE a.aggregate_id = _aggregate_id
   ORDER BY s.sequence_number DESC
   LIMIT 1;
$$;

CREATE OR REPLACE PROCEDURE delete_snapshots_before(_aggregate_id uuid, _sequence_number integer)
LANGUAGE plpgsql AS $$
BEGIN
  DELETE FROM snapshot_records
   WHERE aggregate_id = _aggregate_id
     AND sequence_number < _sequence_number;
END;
$$;

CREATE OR REPLACE FUNCTION aggregates_that_need_snapshots(_last_aggregate_id uuid, _limit integer)
  RETURNS TABLE (aggregate_id uuid)
LANGUAGE plpgsql AS $$
BEGIN
  RETURN QUERY SELECT stream.aggregate_id
    FROM stream_records stream
   WHERE (_last_aggregate_id IS NULL OR stream.aggregate_id > _last_aggregate_id)
     AND snapshot_threshold IS NOT NULL
     AND snapshot_threshold <= (
           (SELECT MAX(events.sequence_number) FROM event_records events WHERE stream.aggregate_id = events.aggregate_id) -
           COALESCE((SELECT MAX(snapshots.sequence_number) FROM snapshot_records snapshots WHERE stream.aggregate_id = snapshots.aggregate_id), 0))
   ORDER BY 1
   LIMIT _limit;
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

CREATE VIEW event_records (aggregate_id, partition_key, sequence_number, created_at, event_type, event_json, command_record_id, xact_id) AS
     SELECT aggregate.aggregate_id,
            event.partition_key,
            event.sequence_number,
            event.created_at,
            type.type,
            enrich_event_json(event) AS event_json,
            command_id,
            event.xact_id
       FROM aggregates aggregate
       JOIN events event ON aggregate.aggregate_id = event.aggregate_id AND aggregate.events_partition_key = event.partition_key
       JOIN event_types type ON event.event_type_id = type.id;

CREATE VIEW stream_records (aggregate_id, events_partition_key, aggregate_type, snapshot_threshold, created_at) AS
     SELECT aggregates.aggregate_id,
            aggregates.events_partition_key,
            aggregate_types.type,
            aggregates.snapshot_threshold,
            aggregates.created_at
       FROM aggregates JOIN aggregate_types ON aggregates.aggregate_type_id = aggregate_types.id;
