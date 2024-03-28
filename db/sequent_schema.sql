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
    id bigint DEFAULT nextval('command_records_id_seq'),
    created_at timestamp with time zone NOT NULL,
    user_id uuid,
    aggregate_id uuid,
    command_type_id SMALLINT NOT NULL REFERENCES command_types (id),
    command_json jsonb NOT NULL,
    event_aggregate_id uuid,
    event_sequence_number integer,
    PRIMARY KEY (id)
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
CREATE TABLE events_organizations PARTITION OF events FOR VALUES FROM ('O') TO ('Og');
ALTER TABLE events_organizations CLUSTER ON events_organizations_pkey;
CREATE TABLE events_aggregate PARTITION OF events FOR VALUES FROM ('A') TO ('Ag');
ALTER TABLE events_aggregate CLUSTER ON events_aggregate_pkey;

TRUNCATE TABLE snapshot_records;
ALTER TABLE snapshot_records
  ALTER COLUMN created_at TYPE timestamptz USING created_at AT TIME ZONE 'Europe/Amsterdam',
  ALTER COLUMN snapshot_type TYPE text,
  ALTER COLUMN snapshot_json TYPE jsonb USING snapshot_json::jsonb,
  DROP CONSTRAINT stream_fkey,
  ADD CONSTRAINT aggregate_fkey FOREIGN KEY (aggregate_id) REFERENCES aggregates (aggregate_id)
    ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE command_records RENAME TO old_command_records;
ALTER TABLE event_records RENAME TO old_event_records;
ALTER TABLE stream_records RENAME TO old_stream_records;

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

CREATE VIEW command_records (id, user_id, aggregate_id, command_type, command_json, created_at, event_aggregate_id, event_sequence_number) AS
  SELECT id,
         user_id,
         aggregate_id,
         (SELECT type FROM command_types WHERE command_types.id = command.command_type_id),
         enrich_command_json(command),
         created_at,
         event_aggregate_id,
         event_sequence_number
    FROM commands command
   UNION ALL
  SELECT id,
         user_id,
         aggregate_id,
         command_type,
         command_json::jsonb,
         created_at,
         event_aggregate_id,
         event_sequence_number
    FROM old_command_records;

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

CREATE VIEW event_records (aggregate_id, partition_key, sequence_number, created_at, event_type, event_json, command_record_id, xact_id) AS
     SELECT aggregate.aggregate_id,
            event.partition_key,
            event.sequence_number,
            event.created_at,
            type.type,
            enrich_event_json(event.*)::text AS event_json,
            command_id,
            event.xact_id
       FROM aggregates aggregate
       JOIN events event ON aggregate.aggregate_id = event.aggregate_id AND aggregate.events_partition_key = event.partition_key
       JOIN event_types type ON event.event_type_id = type.id
      UNION ALL
     SELECT aggregate_id,
            '',
            sequence_number,
            (event_json::jsonb->>'created_at')::timestamptz AS created_at,
            event_type::text,
            event_json::text,
            command_record_id,
            xact_id
       FROM old_event_records;

CREATE VIEW stream_records (aggregate_id, events_partition_key, aggregate_type, snapshot_threshold, created_at) AS
     SELECT aggregates.aggregate_id,
            aggregates.events_partition_key,
            aggregate_types.type,
            aggregates.snapshot_threshold,
            aggregates.created_at
       FROM aggregates JOIN aggregate_types ON aggregates.aggregate_type_id = aggregate_types.id
      UNION ALL
     SELECT aggregate_id,
            NULL,
            aggregate_type,
            snapshot_threshold,
            created_at
       FROM old_stream_records;

INSERT INTO command_types (type) SELECT DISTINCT command_type FROM command_records ORDER BY 1;
INSERT INTO aggregate_types (type) SELECT DISTINCT aggregate_type FROM stream_records ORDER BY 1;
INSERT INTO event_types (type) SELECT DISTINCT event_type FROM old_event_records ORDER BY 1;

CREATE OR REPLACE FUNCTION determine_events_partition_key(_aggregate_id uuid, _organization_id uuid, _event_json jsonb) RETURNS text AS $$
DECLARE
  _event_json_without_nulls jsonb = jsonb_strip_nulls(_event_json);
  _date text;
  _partition_key text;
BEGIN
  _date = (CASE
    WHEN _event_json_without_nulls->'booking_date' IS NOT NULL THEN
      regexp_replace(_event_json_without_nulls->>'booking_date', '[ _-]', '', 'g')
    WHEN _event_json_without_nulls->'year_of_delivery' IS NOT NULL AND _event_json_without_nulls->'month_of_delivery' IS NOT NULL THEN
      trim(to_char((_event_json_without_nulls->>'year_of_delivery')::integer, '0000')) || trim(to_char((_event_json_without_nulls->>'month_of_delivery')::integer, '00'))
    WHEN _event_json_without_nulls->'happened_at' IS NOT NULL THEN
      regexp_replace(LEFT((_event_json_without_nulls->>'happened_at')::text, 10), '[ _-]', '', 'g')
    WHEN _event_json->'book_date' IS NOT NULL THEN
      regexp_replace(LEFT((_event_json_without_nulls->>'book_date')::text, 10), '[ _-]', '', 'g')
    WHEN _event_json->>'event_type' NOT IN (
      'BankCreatedEvent',
      'CompleteOrganizationCreatedEvent',
      'CustomerCreatedEvent',
      'CustomerLedgerAccountCreated',
      'EmailProxyCreated',
      'EstimateNumbersCreated',
      'ExpenseNumbersCreatedEvent',
      'InboxNamesCreated',
      'InvoiceNumbersCreatedEvent',
      'LabelableCreated',
      'LabelCreated',
      'OrganizationBankCreated',
      'OrganizationCreatedAccountEvent',
      'OrganizationCreatedByAccountantEvent',
      'OrganizationCreatedEvent',
      'OrganizationEstimateNumbersCreated',
      'OrganizationExpenseNumbersCreated',
      'OrganizationInvoiceNumbersCreated',
      'OrganizationLedgerCreated',
      'PortalConnectionCreated',
      'PortalConnectionsCreated',
      'ProWowOrganizationCreatedEvent',
      'RootRuleCreated',
      'RuleCreated',
      'UserCreatedEvent',
      'UserCreatedByAccountantEvent'
    ) THEN
      to_char((_event_json->>'created_at')::timestamptz, 'YYYYMMDD')
    ELSE
      NULL
  END);

  IF _date IS NOT NULL AND _organization_id IS NOT NULL THEN
    _partition_key = 'Y' || SUBSTRING(_date FROM 3 FOR 2) || 'O' || LEFT(_organization_id::text, 4);
  ELSIF _organization_id IS NOT NULL THEN
    _partition_key = 'O' || LEFT(_organization_id::text, 4);
  ELSE
    _partition_key = 'A' || LEFT(_aggregate_id::text, 2);
  END IF;

  RETURN _partition_key;
END
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION upsert_aggregate_type(_type aggregate_types.type%TYPE) RETURNS SMALLINT
LANGUAGE plpgsql AS
$$
DECLARE
  _id aggregate_types.id%TYPE;
BEGIN
  SELECT id INTO _id FROM aggregate_types WHERE type = _type;
  IF NOT FOUND THEN
    INSERT INTO aggregate_types (type) VALUES (_type) RETURNING id INTO STRICT _id;
  END IF;
  RETURN _id;
END
$$;

CREATE OR REPLACE FUNCTION upsert_command_type(_type command_types.type%TYPE) RETURNS SMALLINT
LANGUAGE plpgsql AS
$$
DECLARE
  _id command_types.id%TYPE;
BEGIN
  SELECT id INTO _id FROM command_types WHERE type = _type;
  IF NOT FOUND THEN
    RAISE NOTICE 'command type % not found, inserting', _type;
    INSERT INTO command_types (type) VALUES (_type) RETURNING id INTO STRICT _id;
  END IF;
  RETURN _id;
END
$$;

CREATE OR REPLACE FUNCTION upsert_event_type(_type event_types.type%TYPE) RETURNS SMALLINT
LANGUAGE plpgsql AS
$$
DECLARE
  _id event_types.id%TYPE;
BEGIN
  SELECT id INTO _id FROM event_types WHERE type = _type;
  IF NOT FOUND THEN
    INSERT INTO event_types (type) VALUES (_type) RETURNING id INTO STRICT _id;
  END IF;
  RETURN _id;
END
$$;

CREATE OR REPLACE PROCEDURE migrate_command(_command_id commands.id%TYPE)
LANGUAGE plpgsql AS $$
DECLARE
  _command_type text;
  _command_record command_records;
  _command_without_nulls jsonb;
BEGIN
  IF EXISTS (SELECT 1 FROM commands WHERE id = _command_id) THEN
    RETURN;
  END IF;

  SELECT *
    INTO _command_record
    FROM command_records
   WHERE id = _command_id;
  IF NOT FOUND THEN
    -- Event without command
    RETURN;
  END IF;

  _command_without_nulls = jsonb_strip_nulls(_command_record.command_json::jsonb);

  INSERT INTO commands (
    id, created_at, user_id, aggregate_id, command_type_id, command_json,
    event_aggregate_id, event_sequence_number
  ) VALUES (
    _command_id,
    COALESCE((_command_without_nulls->>'created_at')::timestamptz, _command_record.created_at AT TIME ZONE 'Europe/Amsterdam'),
    (_command_without_nulls->>'user_id')::uuid,
    (_command_without_nulls->>'aggregate_id')::uuid,
    upsert_command_type(_command_record.command_type),
    _command_record.command_json::jsonb - '{created_at,organization_id,user_id,aggregate_id,event_aggregate_id,event_sequence_number}'::text[],
    (_command_without_nulls->>'event_aggregate_id')::uuid,
    (_command_without_nulls->'event_sequence_number')::integer
  );
END
$$;

CREATE OR REPLACE FUNCTION migrate_aggregate(_aggregate_id uuid, _provided_events_partition_key text) RETURNS boolean AS $$
DECLARE
  _aggregate_with_first_event RECORD;
  _events_partition_key text;
  _event_json jsonb;
  _event old_event_records;
BEGIN
  SELECT s.*, e.event_type, e.event_json
    INTO _aggregate_with_first_event
    FROM old_stream_records s JOIN old_event_records e ON s.aggregate_id = e.aggregate_id
   WHERE s.aggregate_id = _aggregate_id
     AND e.sequence_number = 1;
  IF NOT FOUND THEN
    RETURN FALSE;
  END IF;

  _event_json = _aggregate_with_first_event.event_json::jsonb;
  _events_partition_key = COALESCE(
    _provided_events_partition_key,
    determine_events_partition_key(_aggregate_with_first_event.aggregate_id, NULL, _event_json)
  );

  INSERT INTO aggregates (aggregate_id, created_at, aggregate_type_id, events_partition_key, snapshot_threshold)
  VALUES (
    _aggregate_id,
    _aggregate_with_first_event.created_at AT TIME ZONE 'Europe/Amsterdam',
    upsert_aggregate_type(_aggregate_with_first_event.aggregate_type),
    COALESCE(_events_partition_key, ''),
    _aggregate_with_first_event.snapshot_threshold
  );

  FOR _event IN SELECT * FROM old_event_records WHERE aggregate_id = _aggregate_id ORDER BY sequence_number LOOP
    _event_json = _event.event_json::jsonb;

    CALL migrate_command(_event.command_record_id);

    INSERT INTO events (partition_key, aggregate_id, sequence_number, created_at, command_id, event_type_id, event_json, xact_id)
    VALUES (
        _events_partition_key,
        _aggregate_id,
        _event.sequence_number,
        (_event_json->>'created_at')::timestamptz,
        _event.command_record_id,
        upsert_event_type(_event.event_type),
        _event_json - '{aggregate_id,organization_id,created_at,sequence_number}'::text[],
        _event.xact_id
    );
  END LOOP;

  DELETE FROM old_event_records WHERE aggregate_id = _aggregate_id;
  DELETE FROM old_stream_records WHERE aggregate_id = _aggregate_id;

  RETURN TRUE;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION load_old_events(
  _aggregate_id old_stream_records.aggregate_id%TYPE,
  _use_snapshots boolean DEFAULT TRUE,
  _until event_records.created_at%TYPE DEFAULT NULL
) RETURNS SETOF aggregate_event_type AS $$
DECLARE
  _snapshot_event snapshot_records;
  _snapshot_event_sequence_number integer = 0;
  _stream_record old_stream_records;
BEGIN
  SELECT *
    INTO _stream_record
    FROM old_stream_records
   WHERE old_stream_records.aggregate_id = _aggregate_id;
  IF NOT FOUND THEN
    RETURN;
  END IF;

  IF _use_snapshots THEN
    SELECT *
      INTO _snapshot_event
      FROM snapshot_records snapshot
     WHERE snapshot.aggregate_id = _aggregate_id
     ORDER BY snapshot.sequence_number DESC
     LIMIT 1;
    IF FOUND THEN
      RETURN NEXT (_stream_record.aggregate_type,
                   _stream_record.aggregate_id,
                   '',
                   _stream_record.snapshot_threshold,
                   _snapshot_event.snapshot_type::text,
                   _snapshot_event.snapshot_json::jsonb);
      _snapshot_event_sequence_number = _snapshot_event.sequence_number;
    END IF;
  END IF;

  RETURN QUERY SELECT _stream_record.aggregate_type,
                      _stream_record.aggregate_id,
                      '',
                      _stream_record.snapshot_threshold,
                      event.event_type::text,
                      event.event_json::jsonb
                 FROM old_event_records event
                WHERE aggregate_id = _aggregate_id::uuid
                  AND sequence_number >= _snapshot_event_sequence_number
                  AND (_until IS NULL OR created_at < _until)
                ORDER BY sequence_number;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION load_event(
  _aggregate_id uuid,
  _sequence_number integer
) RETURNS SETOF aggregate_event_type
LANGUAGE plpgsql AS $$
DECLARE
  _aggregate aggregates;
  _aggregate_type text;
BEGIN
  SELECT * INTO _aggregate
    FROM aggregates
   WHERE aggregate_id = _aggregate_id;
  IF NOT FOUND THEN
    RETURN QUERY SELECT aggregate_type::text, _aggregate_id, ''::text, snapshot_threshold, event_type::text, event_json::jsonb
                   FROM old_event_records event JOIN old_stream_records stream ON event.aggregate_id = stream.aggregate_id
                  WHERE stream.aggregate_id = _aggregate_id
                    AND sequence_number = _sequence_number;
    RETURN;
  END IF;

  SELECT type INTO STRICT _aggregate_type
    FROM aggregate_types
   WHERE id = _aggregate.aggregate_type_id;

  RETURN QUERY SELECT _aggregate_type, aggregate_id, _aggregate.events_partition_key, _aggregate.snapshot_threshold, event_type, event_json::jsonb
                 FROM event_records
                WHERE aggregate_id = _aggregate_id
                  AND sequence_number = _sequence_number;
END;
$$;

CREATE OR REPLACE FUNCTION load_events(
  _aggregate_ids jsonb,
  _use_snapshots boolean DEFAULT TRUE,
  _until timestamptz DEFAULT NULL
) RETURNS SETOF aggregate_event_type
LANGUAGE plpgsql AS $$
DECLARE
  _aggregate_type text;
  _aggregate_id aggregates.aggregate_id%TYPE;
  _aggregate aggregates;
  _snapshot snapshot_records;
  _start_sequence_number events.sequence_number%TYPE;
BEGIN
  FOR _aggregate_id IN SELECT * FROM jsonb_array_elements_text(_aggregate_ids) LOOP
    SELECT * INTO _aggregate FROM aggregates WHERE aggregates.aggregate_id = _aggregate_id;
    IF NOT FOUND THEN
      RETURN QUERY SELECT * FROM load_old_events(_aggregate_id::uuid, _use_snapshots, _until);
      CONTINUE;
    END IF;

    SELECT type INTO STRICT _aggregate_type
      FROM aggregate_types
     WHERE id = _aggregate.aggregate_type_id;

    _start_sequence_number = 0;
    IF _use_snapshots THEN
      SELECT * INTO _snapshot FROM snapshot_records snapshots WHERE snapshots.aggregate_id = _aggregate.aggregate_id ORDER BY sequence_number DESC LIMIT 1;
      IF FOUND THEN
        _start_sequence_number := _snapshot.sequence_number;
        RETURN NEXT (_aggregate_type,
                     _aggregate.aggregate_id,
                     _aggregate.events_partition_key,
                     _aggregate.snapshot_threshold,
                     _snapshot.snapshot_type,
                     _snapshot.snapshot_json);
      END IF;
    END IF;
    RETURN QUERY SELECT _aggregate_type,
                        _aggregate.aggregate_id,
                        _aggregate.events_partition_key,
                        _aggregate.snapshot_threshold,
                        event_types.type,
                        enrich_event_json(events)
                   FROM events
                       INNER JOIN event_types ON events.event_type_id = event_types.id
                  WHERE events.partition_key = _aggregate.events_partition_key
                    AND events.aggregate_id = _aggregate.aggregate_id
                    AND events.sequence_number >= _start_sequence_number
                    AND (_until IS NULL OR events.created_at < _until)
                  ORDER BY events.sequence_number;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION store_command(_command jsonb) RETURNS bigint
LANGUAGE plpgsql AS $$
DECLARE
  _id commands.id%TYPE;
  _command_without_nulls jsonb = jsonb_strip_nulls(_command->'command_json');
BEGIN
  INSERT INTO commands (
    created_at, user_id, aggregate_id, command_type_id, command_json,
    event_aggregate_id, event_sequence_number
  ) VALUES (
    (_command->>'created_at')::timestamptz,
    (_command_without_nulls->>'user_id')::uuid,
    (_command_without_nulls->>'aggregate_id')::uuid,
    upsert_command_type(_command->>'command_type'),
    (_command->'command_json') - '{command_type,created_at,organization_id,user_id,aggregate_id,event_aggregate_id,event_sequence_number}'::text[],
    (_command_without_nulls->>'event_aggregate_id')::uuid,
    (_command_without_nulls->'event_sequence_number')::integer
  ) RETURNING id INTO STRICT _id;
  RETURN _id;
END;
$$;

CREATE OR REPLACE PROCEDURE store_events(_command jsonb, _aggregates_with_events jsonb)
LANGUAGE plpgsql AS $$
DECLARE
  _command_id commands.id%TYPE;
  _aggregate jsonb;
  _aggregate_without_nulls jsonb;
  _events jsonb;
  _event jsonb;
  _aggregate_id aggregates.aggregate_id%TYPE;
  _created_at aggregates.created_at%TYPE;
  _provided_events_partition_key aggregates.events_partition_key%TYPE;
  _existing_events_partition_key aggregates.events_partition_key%TYPE;
  _events_partition_key aggregates.events_partition_key%TYPE;
  _snapshot_threshold aggregates.snapshot_threshold%TYPE;
  _sequence_number events.sequence_number%TYPE;
BEGIN
  _command_id = store_command(_command);

  FOR _aggregate, _events IN SELECT row->0, row->1 FROM jsonb_array_elements(_aggregates_with_events) AS row LOOP
    _aggregate_id = _aggregate->>'aggregate_id';
    _aggregate_without_nulls = jsonb_strip_nulls(_aggregate);
    _snapshot_threshold = _aggregate_without_nulls->'snapshot_threshold';
    _provided_events_partition_key = _aggregate_without_nulls->>'events_partition_key';

    PERFORM migrate_aggregate(_aggregate_id, _provided_events_partition_key);

    SELECT events_partition_key INTO _existing_events_partition_key FROM aggregates WHERE aggregate_id = _aggregate_id;
    IF NOT FOUND THEN
      _events_partition_key = COALESCE(_provided_events_partition_key, determine_events_partition_key(_aggregate_id, NULL, _events->0->'event_json'));
    ELSE
      _events_partition_key = COALESCE(_provided_events_partition_key, _existing_events_partition_key);
    END IF;


    INSERT INTO aggregates (aggregate_id, created_at, aggregate_type_id, events_partition_key, snapshot_threshold)
    VALUES (
      _aggregate_id,
      (_events->0->>'created_at')::timestamptz,
      upsert_aggregate_type(_aggregate->>'aggregate_type'),
      COALESCE(_events_partition_key, ''),
      _snapshot_threshold
    ) ON CONFLICT (aggregate_id)
      DO UPDATE SET events_partition_key = EXCLUDED.events_partition_key,
                    snapshot_threshold = EXCLUDED.snapshot_threshold
              WHERE aggregates.events_partition_key <> EXCLUDED.events_partition_key
                 OR aggregates.snapshot_threshold <> EXCLUDED.snapshot_threshold;

    FOR _event IN SELECT * FROM jsonb_array_elements(_events) LOOP
      _created_at = (_event->>'created_at')::timestamptz;
      _sequence_number = _event->'event_json'->>'sequence_number';
      INSERT INTO events (partition_key, aggregate_id, sequence_number, created_at, command_id, event_type_id, event_json)
          VALUES (
             _events_partition_key,
             _aggregate_id,
             _sequence_number,
             _created_at,
             _command_id,
             upsert_event_type(_event->>'event_type'),
             (_event->'event_json') - '{aggregate_id,created_at,event_type,organization_id,sequence_number,stream_record_id}'::text[]
           );
    END LOOP;
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

    PERFORM migrate_aggregate(_aggregate_id, NULL);

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

  DELETE FROM old_command_records
   WHERE (_aggregate_id IS NULL OR aggregate_id = _aggregate_id)
     AND NOT EXISTS (SELECT 1 FROM events WHERE command_id = old_command_records.id)
     AND NOT EXISTS (SELECT 1 FROM old_event_records WHERE command_record_id = old_command_records.id);
  DELETE FROM commands
   WHERE (_aggregate_id IS NULL OR aggregate_id = _aggregate_id)
     AND NOT EXISTS (SELECT 1 FROM events WHERE command_id = commands.id)
     AND NOT EXISTS (SELECT 1 FROM old_event_records WHERE command_record_id = commands.id);
END;
$$;

CREATE OR REPLACE PROCEDURE permanently_delete_event_streams(_aggregate_ids jsonb)
LANGUAGE plpgsql AS $$
BEGIN
  DELETE FROM old_event_records
   USING jsonb_array_elements_text(_aggregate_ids) AS ids (id)
   WHERE old_event_records.aggregate_id = ids.id::uuid;
  DELETE FROM old_stream_records
   USING jsonb_array_elements_text(_aggregate_ids) AS ids (id)
   WHERE old_stream_records.aggregate_id = ids.id::uuid;

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
