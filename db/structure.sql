SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: sequent_schema; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA sequent_schema;


--
-- Name: aggregate_event_type; Type: TYPE; Schema: sequent_schema; Owner: -
--

CREATE TYPE sequent_schema.aggregate_event_type AS (
	aggregate_type text,
	aggregate_id uuid,
	events_partition_key text,
	event_sequence_number integer,
	event_type text,
	event_json jsonb
);


--
-- Name: aggregates_that_need_snapshots(uuid, integer, jsonb); Type: FUNCTION; Schema: sequent_schema; Owner: -
--

CREATE FUNCTION sequent_schema.aggregates_that_need_snapshots(_last_aggregate_id uuid, _limit integer, _snapshot_version_by_type jsonb DEFAULT '{}'::jsonb) RETURNS TABLE(aggregate_id uuid)
    LANGUAGE plpgsql
    SET search_path TO 'sequent_schema'
    AS $$
BEGIN
  RETURN QUERY SELECT a.aggregate_id
    FROM aggregates_that_need_snapshots s
    JOIN aggregates a ON s.aggregate_id = a.aggregate_id
    JOIN aggregate_types type ON a.aggregate_type_id = type.id
   WHERE s.snapshot_outdated_at IS NOT NULL
     AND s.snapshot_version = COALESCE((_snapshot_version_by_type->>(type.type))::integer, 1)
     AND (_last_aggregate_id IS NULL OR s.aggregate_id > _last_aggregate_id)
   ORDER BY 1
   LIMIT _limit;
END;
$$;


--
-- Name: delete_all_snapshots(timestamp with time zone); Type: PROCEDURE; Schema: sequent_schema; Owner: -
--

CREATE PROCEDURE sequent_schema.delete_all_snapshots(IN _now timestamp with time zone DEFAULT now())
    LANGUAGE plpgsql
    SET search_path TO 'sequent_schema'
    AS $$
BEGIN
  UPDATE aggregates_that_need_snapshots
     SET snapshot_outdated_at = _now
   WHERE snapshot_outdated_at IS NULL;
  DELETE FROM snapshot_records;
END;
$$;


--
-- Name: delete_snapshots_before(uuid, integer, timestamp with time zone, jsonb); Type: PROCEDURE; Schema: sequent_schema; Owner: -
--

CREATE PROCEDURE sequent_schema.delete_snapshots_before(IN _aggregate_id uuid, IN _sequence_number integer, IN _now timestamp with time zone DEFAULT now(), IN _snapshot_version_by_type jsonb DEFAULT '{}'::jsonb)
    LANGUAGE plpgsql
    SET search_path TO 'sequent_schema'
    AS $$
BEGIN
  DELETE FROM snapshot_records s
   WHERE aggregate_id = _aggregate_id
     AND snapshot_version = COALESCE(
           (SELECT _snapshot_version_by_type->>(type.type)
              FROM aggregates
              JOIN aggregate_types type ON aggregate_type_id = type.id
             WHERE s.aggregate_id = aggregates.aggregate_id)::integer,
           1
         )
     AND sequence_number < _sequence_number;

  UPDATE aggregates_that_need_snapshots a
     SET snapshot_outdated_at = _now
   WHERE aggregate_id = _aggregate_id
     AND snapshot_outdated_at IS NULL
     AND NOT EXISTS (SELECT 1 FROM snapshot_records s WHERE aggregate_id = _aggregate_id AND a.snapshot_version = s.snapshot_version);
END;
$$;


SET default_tablespace = '';

--
-- Name: commands; Type: TABLE; Schema: sequent_schema; Owner: -
--

CREATE TABLE sequent_schema.commands (
    id bigint NOT NULL,
    created_at timestamp with time zone NOT NULL,
    user_id uuid,
    aggregate_id uuid,
    command_type_id smallint NOT NULL,
    command_json jsonb NOT NULL,
    event_aggregate_id uuid,
    event_sequence_number integer
)
PARTITION BY RANGE (id);


--
-- Name: enrich_command_json(sequent_schema.commands); Type: FUNCTION; Schema: sequent_schema; Owner: -
--

CREATE FUNCTION sequent_schema.enrich_command_json(command sequent_schema.commands) RETURNS jsonb
    LANGUAGE plpgsql STRICT
    SET search_path TO 'sequent_schema'
    AS $$
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


--
-- Name: events; Type: TABLE; Schema: sequent_schema; Owner: -
--

CREATE TABLE sequent_schema.events (
    aggregate_id uuid NOT NULL,
    partition_key text DEFAULT ''::text NOT NULL,
    sequence_number integer NOT NULL,
    created_at timestamp with time zone NOT NULL,
    command_id bigint NOT NULL,
    event_type_id smallint NOT NULL,
    event_json jsonb NOT NULL,
    xact_id bigint DEFAULT ((pg_current_xact_id())::text)::bigint
)
PARTITION BY RANGE (partition_key);


--
-- Name: enrich_event_json(sequent_schema.events); Type: FUNCTION; Schema: sequent_schema; Owner: -
--

CREATE FUNCTION sequent_schema.enrich_event_json(event sequent_schema.events) RETURNS jsonb
    LANGUAGE plpgsql STRICT
    SET search_path TO 'sequent_schema'
    AS $$
BEGIN
  RETURN jsonb_build_object(
      'aggregate_id', event.aggregate_id,
      'sequence_number', event.sequence_number,
      'created_at', event.created_at
    )
    || event.event_json;
END
$$;


--
-- Name: load_event(uuid, integer); Type: FUNCTION; Schema: sequent_schema; Owner: -
--

CREATE FUNCTION sequent_schema.load_event(_aggregate_id uuid, _sequence_number integer) RETURNS SETOF sequent_schema.aggregate_event_type
    LANGUAGE plpgsql STRICT
    SET search_path TO 'sequent_schema'
    AS $$
BEGIN
  RETURN QUERY SELECT aggregate_types.type,
         a.aggregate_id,
         a.events_partition_key,
         e.sequence_number,
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


--
-- Name: load_events(jsonb, boolean, timestamp with time zone, jsonb); Type: FUNCTION; Schema: sequent_schema; Owner: -
--

CREATE FUNCTION sequent_schema.load_events(_aggregate_ids jsonb, _use_snapshots boolean DEFAULT true, _until timestamp with time zone DEFAULT NULL::timestamp with time zone, _snapshot_version_by_type jsonb DEFAULT '{}'::jsonb) RETURNS SETOF sequent_schema.aggregate_event_type
    LANGUAGE plpgsql
    SET search_path TO 'sequent_schema'
    AS $$
DECLARE
  _aggregate_id aggregates.aggregate_id%TYPE;
BEGIN
  FOR _aggregate_id IN SELECT * FROM jsonb_array_elements_text(_aggregate_ids) LOOP
    -- Use a single query to avoid race condition with UPDATEs to the events partition key
    -- in case transaction isolation level is lower than repeatable read (the default of
    -- PostgreSQL is read committed).
    RETURN QUERY WITH
      aggregate AS MATERIALIZED (
        SELECT aggregate_types.type, aggregate_id, events_partition_key
          FROM aggregates
          JOIN aggregate_types ON aggregate_type_id = aggregate_types.id
         WHERE aggregate_id = _aggregate_id
      ),
      snapshot AS MATERIALIZED (
        SELECT s.*
          FROM snapshot_records s JOIN aggregate ON s.aggregate_id = aggregate.aggregate_id
         WHERE _use_snapshots
           AND s.aggregate_id = _aggregate_id
           AND (_until IS NULL OR created_at < _until)
           AND snapshot_version = COALESCE((_snapshot_version_by_type->(aggregate.type))::integer, 1)
         ORDER BY s.sequence_number DESC LIMIT 1
      )
    SELECT a.*, 0 AS sequence_number, s.snapshot_type, s.snapshot_json FROM aggregate a, snapshot s
    UNION ALL
    SELECT a.*, e.sequence_number, event_types.type, enrich_event_json(e)
       FROM aggregate a
       JOIN events e ON (a.events_partition_key, a.aggregate_id) = (e.partition_key, e.aggregate_id)
       JOIN event_types ON e.event_type_id = event_types.id
      WHERE e.sequence_number >= COALESCE((SELECT sequence_number FROM snapshot), 0)
        AND (_until IS NULL OR e.created_at < _until)
    ORDER BY sequence_number ASC;
  END LOOP;
END;
$$;


--
-- Name: load_latest_snapshot(uuid, jsonb); Type: FUNCTION; Schema: sequent_schema; Owner: -
--

CREATE FUNCTION sequent_schema.load_latest_snapshot(_aggregate_id uuid, _snapshot_version_by_type jsonb DEFAULT '{}'::jsonb) RETURNS sequent_schema.aggregate_event_type
    LANGUAGE sql
    SET search_path TO 'sequent_schema'
    AS $$
  SELECT t.type,
         a.aggregate_id,
         a.events_partition_key,
         0 AS sequence_number,
         s.snapshot_type,
         s.snapshot_json
    FROM aggregates a
    JOIN aggregate_types t on a.aggregate_type_id = t.id
    JOIN snapshot_records s ON a.aggregate_id = s.aggregate_id
   WHERE a.aggregate_id = _aggregate_id
     AND s.snapshot_version = COALESCE((_snapshot_version_by_type->>(t.type))::integer, 1)
   ORDER BY s.sequence_number DESC
   LIMIT 1;
$$;


--
-- Name: permanently_delete_commands_without_events(uuid); Type: PROCEDURE; Schema: sequent_schema; Owner: -
--

CREATE PROCEDURE sequent_schema.permanently_delete_commands_without_events(IN _aggregate_id uuid)
    LANGUAGE plpgsql
    SET search_path TO 'sequent_schema'
    AS $$
BEGIN
  IF _aggregate_id IS NULL THEN
    RAISE EXCEPTION 'aggregate_id must be specified to delete commands';
  END IF;

  DELETE FROM commands
   WHERE aggregate_id = _aggregate_id
     AND NOT EXISTS (SELECT 1 FROM events WHERE command_id = commands.id);
END;
$$;


--
-- Name: permanently_delete_event_streams(jsonb); Type: PROCEDURE; Schema: sequent_schema; Owner: -
--

CREATE PROCEDURE sequent_schema.permanently_delete_event_streams(IN _aggregate_ids jsonb)
    LANGUAGE plpgsql
    SET search_path TO 'sequent_schema'
    AS $$
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


--
-- Name: register_types(jsonb); Type: PROCEDURE; Schema: sequent_schema; Owner: -
--

CREATE PROCEDURE sequent_schema.register_types(IN _types jsonb)
    LANGUAGE plpgsql
    SET search_path TO 'sequent_schema'
    AS $$
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
      FROM jsonb_array_elements_text(_types->'aggregate_types') AS type
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


--
-- Name: save_events_on_delete_trigger(); Type: FUNCTION; Schema: sequent_schema; Owner: -
--

CREATE FUNCTION sequent_schema.save_events_on_delete_trigger() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'sequent_schema'
    AS $$
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
$$;


--
-- Name: save_events_on_update_trigger(); Type: FUNCTION; Schema: sequent_schema; Owner: -
--

CREATE FUNCTION sequent_schema.save_events_on_update_trigger() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'sequent_schema'
    AS $$
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
$$;


--
-- Name: select_aggregates_for_snapshotting(integer, timestamp with time zone, timestamp with time zone, jsonb); Type: FUNCTION; Schema: sequent_schema; Owner: -
--

CREATE FUNCTION sequent_schema.select_aggregates_for_snapshotting(_limit integer, _reschedule_snapshot_scheduled_before timestamp with time zone, _now timestamp with time zone DEFAULT now(), _snapshot_version_by_type jsonb DEFAULT '{}'::jsonb) RETURNS TABLE(aggregate_id uuid, aggregate_type text, snapshot_version integer)
    LANGUAGE plpgsql
    SET search_path TO 'sequent_schema'
    AS $$
BEGIN
  RETURN QUERY WITH scheduled AS MATERIALIZED (
    SELECT s.*, t.type AS aggregate_type
      FROM aggregates_that_need_snapshots AS s
      JOIN aggregates a ON s.aggregate_id = a.aggregate_id
      JOIN aggregate_types t ON a.aggregate_type_id = t.id
     WHERE s.snapshot_outdated_at IS NOT NULL
       AND s.snapshot_version = COALESCE((_snapshot_version_by_type->>(t.type))::integer, 1)
     ORDER BY s.snapshot_outdated_at ASC, s.snapshot_sequence_number_high_water_mark DESC, s.aggregate_id ASC
     LIMIT _limit
       FOR UPDATE OF s SKIP LOCKED
   ), updated AS MATERIALIZED (
     UPDATE aggregates_that_need_snapshots AS row
        SET snapshot_scheduled_at = _now
       FROM scheduled
      WHERE row.aggregate_id = scheduled.aggregate_id
        AND row.snapshot_version = scheduled.snapshot_version
        AND (row.snapshot_scheduled_at IS NULL OR row.snapshot_scheduled_at < _reschedule_snapshot_scheduled_before)
     RETURNING scheduled.*
   )
   SELECT updated.aggregate_id, updated.aggregate_type, updated.snapshot_version
     FROM updated
    ORDER BY snapshot_outdated_at ASC, snapshot_sequence_number_high_water_mark DESC, aggregate_id ASC;
END;
$$;


--
-- Name: store_aggregates(jsonb); Type: PROCEDURE; Schema: sequent_schema; Owner: -
--

CREATE PROCEDURE sequent_schema.store_aggregates(IN _aggregates_with_events jsonb)
    LANGUAGE plpgsql
    SET search_path TO 'sequent_schema'
    AS $$
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
      INSERT INTO aggregates_that_need_snapshots AS row (aggregate_id, snapshot_version, snapshot_outdated_at)
      VALUES (_aggregate_id, COALESCE((_aggregate->>'snapshot_version')::integer, 1), _snapshot_outdated_at)
          ON CONFLICT (aggregate_id, snapshot_version) DO UPDATE
         SET snapshot_outdated_at = LEAST(row.snapshot_outdated_at, EXCLUDED.snapshot_outdated_at)
       WHERE row.snapshot_outdated_at IS DISTINCT FROM EXCLUDED.snapshot_outdated_at;
    END IF;
  END LOOP;
END;
$$;


--
-- Name: store_command(jsonb); Type: FUNCTION; Schema: sequent_schema; Owner: -
--

CREATE FUNCTION sequent_schema.store_command(_command jsonb) RETURNS bigint
    LANGUAGE plpgsql STRICT
    SET search_path TO 'sequent_schema'
    AS $$
DECLARE
  _id commands.id%TYPE;
  _command_json jsonb = _command->'command_json';
BEGIN
  INSERT INTO commands (
    created_at, user_id, aggregate_id, command_type_id, command_json,
    event_aggregate_id, event_sequence_number
  ) VALUES (
    (_command->>'created_at')::timestamptz,
    (_command_json->>'user_id')::uuid,
    (_command_json->>'aggregate_id')::uuid,
    (SELECT id FROM command_types WHERE type = _command->>'command_type'),
    (_command->'command_json') - '{command_type,created_at,user_id,aggregate_id,event_aggregate_id,event_sequence_number}'::text[],
    (_command_json->>'event_aggregate_id')::uuid,
    NULLIF(_command_json->'event_sequence_number', 'null'::jsonb)::integer
  ) RETURNING id INTO STRICT _id;
  RETURN _id;
END;
$$;


--
-- Name: store_events(jsonb, jsonb); Type: PROCEDURE; Schema: sequent_schema; Owner: -
--

CREATE PROCEDURE sequent_schema.store_events(IN _command jsonb, IN _aggregates_with_events jsonb)
    LANGUAGE plpgsql
    SET search_path TO 'sequent_schema'
    AS $$
DECLARE
  _command_id commands.id%TYPE;
  _aggregates jsonb;
  _aggregate jsonb;
  _events jsonb;
  _aggregate_id aggregates.aggregate_id%TYPE;
  _events_partition_key aggregates.events_partition_key%TYPE;
  _last_sequence_number events.sequence_number%TYPE;
  _next_sequence_number events.sequence_number%TYPE;
BEGIN
  CALL update_types(_command, _aggregates_with_events);

  _command_id = store_command(_command);

  CALL store_aggregates(_aggregates_with_events);

  FOR _aggregate, _events IN SELECT row->0, row->1 FROM jsonb_array_elements(_aggregates_with_events) AS row
                             ORDER BY row->0->'aggregate_id', row->1->0->'event_json'->'sequence_number'
  LOOP
    _aggregate_id = _aggregate->>'aggregate_id';
    SELECT events_partition_key INTO STRICT _events_partition_key FROM aggregates WHERE aggregate_id = _aggregate_id;

    SELECT sequence_number
      INTO _last_sequence_number
      FROM events
     WHERE partition_key = _events_partition_key
       AND aggregate_id = _aggregate_id
     ORDER BY 1 DESC
     LIMIT 1;

    SELECT MIN(event->'event_json'->>'sequence_number')
      INTO _next_sequence_number
      FROM jsonb_array_elements(_events) AS event;

    -- Check sequence number of first new event to ensure optimistic locking works correctly
    -- (otherwise two concurrent transactions could insert events with different first/next
    -- sequence number and no constraint violation would be raised).
    IF _last_sequence_number IS NULL AND _next_sequence_number <> 1 THEN
      RAISE EXCEPTION 'sequence_number of first event must be 1, but was % (aggregate %)', _next_sequence_number, _aggregate_id
            USING ERRCODE = 'integrity_constraint_violation';
    ELSIF _last_sequence_number IS NOT NULL AND _next_sequence_number > _last_sequence_number + 1 THEN
      RAISE EXCEPTION 'sequence_number must be consecutive, but last sequence number was % and next is % (aggregate %)',
                      _last_sequence_number, _next_sequence_number, _aggregate_id
            USING ERRCODE = 'integrity_constraint_violation';
    END IF;

    INSERT INTO events (partition_key, aggregate_id, sequence_number, created_at, command_id, event_type_id, event_json)
    SELECT _events_partition_key,
           _aggregate_id,
           (event->'event_json'->'sequence_number')::integer,
           (event->>'created_at')::timestamptz,
           _command_id,
           (SELECT id FROM event_types WHERE type = event->>'event_type'),
           (event->'event_json') - '{aggregate_id,created_at,event_type,sequence_number}'::text[]
      FROM jsonb_array_elements(_events) AS event
     ORDER BY 1, 2, 3;
  END LOOP;

  _aggregates = (SELECT jsonb_agg(row->0) FROM jsonb_array_elements(_aggregates_with_events) AS row);
  CALL update_unique_keys(_aggregates);
END;
$$;


--
-- Name: store_snapshots(jsonb); Type: PROCEDURE; Schema: sequent_schema; Owner: -
--

CREATE PROCEDURE sequent_schema.store_snapshots(IN _snapshots jsonb)
    LANGUAGE plpgsql
    SET search_path TO 'sequent_schema'
    AS $$
DECLARE
  _aggregate_id uuid;
  _snapshot jsonb;
  _snapshot_version integer;
  _sequence_number snapshot_records.sequence_number%TYPE;
BEGIN
  FOR _snapshot IN SELECT * FROM jsonb_array_elements(_snapshots) LOOP
    _aggregate_id = _snapshot->>'aggregate_id';
    _sequence_number = _snapshot->'sequence_number';
    _snapshot_version = _snapshot->'snapshot_version';

    INSERT INTO aggregates_that_need_snapshots AS row (aggregate_id, snapshot_version, snapshot_sequence_number_high_water_mark)
    VALUES (_aggregate_id, _snapshot_version, _sequence_number)
        ON CONFLICT (aggregate_id, snapshot_version) DO UPDATE
       SET snapshot_sequence_number_high_water_mark =
             GREATEST(row.snapshot_sequence_number_high_water_mark, EXCLUDED.snapshot_sequence_number_high_water_mark),
           snapshot_outdated_at = NULL,
           snapshot_scheduled_at = NULL;

    INSERT INTO snapshot_records (aggregate_id, snapshot_version, sequence_number, created_at, snapshot_type, snapshot_json)
    VALUES (
      _aggregate_id,
      _snapshot_version,
      _sequence_number,
      (_snapshot->>'created_at')::timestamptz,
      _snapshot->>'snapshot_type',
      _snapshot->'snapshot_json'
    );
  END LOOP;
END;
$$;


--
-- Name: update_types(jsonb, jsonb); Type: PROCEDURE; Schema: sequent_schema; Owner: -
--

CREATE PROCEDURE sequent_schema.update_types(IN _command jsonb, IN _aggregates_with_events jsonb)
    LANGUAGE plpgsql
    SET search_path TO 'sequent_schema'
    AS $$
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


--
-- Name: update_unique_keys(jsonb); Type: PROCEDURE; Schema: sequent_schema; Owner: -
--

CREATE PROCEDURE sequent_schema.update_unique_keys(IN _stream_records jsonb)
    LANGUAGE plpgsql
    SET search_path TO 'sequent_schema'
    AS $$
DECLARE
  _aggregate jsonb;
  _aggregate_id aggregates.aggregate_id%TYPE;
  _unique_keys jsonb;
BEGIN
  FOR _aggregate IN SELECT aggregate FROM jsonb_array_elements(_stream_records) AS aggregate ORDER BY aggregate->>'aggregate_id' LOOP
    _aggregate_id = _aggregate->>'aggregate_id';
    _unique_keys = COALESCE(_aggregate->'unique_keys', '{}'::jsonb);

    DELETE FROM aggregate_unique_keys AS target
     WHERE target.aggregate_id = _aggregate_id
       AND NOT (_unique_keys ? target.scope);
  END LOOP;

  FOR _aggregate IN SELECT aggregate FROM jsonb_array_elements(_stream_records) AS aggregate ORDER BY aggregate->>'aggregate_id' LOOP
    _aggregate_id = _aggregate->>'aggregate_id';
    _unique_keys = COALESCE(_aggregate->'unique_keys', '{}'::jsonb);

    INSERT INTO aggregate_unique_keys AS target (aggregate_id, scope, key)
    SELECT _aggregate_id, key, value
      FROM jsonb_each(_unique_keys) AS x
     ORDER BY 1, 2
        ON CONFLICT (aggregate_id, scope) DO UPDATE
       SET key = EXCLUDED.key
     WHERE target.key <> EXCLUDED.key;
  END LOOP;
EXCEPTION
  WHEN unique_violation THEN
    RAISE unique_violation
    USING MESSAGE = 'duplicate unique key value for aggregate ' || (_aggregate->>'aggregate_type') || ' ' || _aggregate_id || ' (' || SQLERRM || ')';
END;
$$;


SET default_table_access_method = heap;

--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: aggregate_types; Type: TABLE; Schema: sequent_schema; Owner: -
--

CREATE TABLE sequent_schema.aggregate_types (
    id smallint NOT NULL,
    type text NOT NULL
);


--
-- Name: aggregate_types_id_seq; Type: SEQUENCE; Schema: sequent_schema; Owner: -
--

ALTER TABLE sequent_schema.aggregate_types ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME sequent_schema.aggregate_types_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: aggregate_unique_keys; Type: TABLE; Schema: sequent_schema; Owner: -
--

CREATE TABLE sequent_schema.aggregate_unique_keys (
    aggregate_id uuid NOT NULL,
    scope text NOT NULL,
    key jsonb NOT NULL
);


--
-- Name: aggregates; Type: TABLE; Schema: sequent_schema; Owner: -
--

CREATE TABLE sequent_schema.aggregates (
    aggregate_id uuid NOT NULL,
    events_partition_key text DEFAULT ''::text NOT NULL,
    aggregate_type_id smallint NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
)
PARTITION BY RANGE (aggregate_id);


--
-- Name: aggregates_default; Type: TABLE; Schema: sequent_schema; Owner: -
--

CREATE TABLE sequent_schema.aggregates_default (
    aggregate_id uuid NOT NULL,
    events_partition_key text DEFAULT ''::text NOT NULL,
    aggregate_type_id smallint NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: aggregates_that_need_snapshots; Type: TABLE; Schema: sequent_schema; Owner: -
--

CREATE TABLE sequent_schema.aggregates_that_need_snapshots (
    aggregate_id uuid NOT NULL,
    snapshot_sequence_number_high_water_mark integer,
    snapshot_outdated_at timestamp with time zone,
    snapshot_scheduled_at timestamp with time zone,
    snapshot_version integer NOT NULL
);


--
-- Name: TABLE aggregates_that_need_snapshots; Type: COMMENT; Schema: sequent_schema; Owner: -
--

COMMENT ON TABLE sequent_schema.aggregates_that_need_snapshots IS 'Contains a row for every aggregate with more events than its snapshot threshold.';


--
-- Name: COLUMN aggregates_that_need_snapshots.snapshot_sequence_number_high_water_mark; Type: COMMENT; Schema: sequent_schema; Owner: -
--

COMMENT ON COLUMN sequent_schema.aggregates_that_need_snapshots.snapshot_sequence_number_high_water_mark IS 'The highest sequence number of the stored snapshot. Kept when snapshot are deleted to more easily query aggregates that need snapshotting the most';


--
-- Name: COLUMN aggregates_that_need_snapshots.snapshot_outdated_at; Type: COMMENT; Schema: sequent_schema; Owner: -
--

COMMENT ON COLUMN sequent_schema.aggregates_that_need_snapshots.snapshot_outdated_at IS 'Not NULL indicates a snapshot is needed since the stored timestamp';


--
-- Name: COLUMN aggregates_that_need_snapshots.snapshot_scheduled_at; Type: COMMENT; Schema: sequent_schema; Owner: -
--

COMMENT ON COLUMN sequent_schema.aggregates_that_need_snapshots.snapshot_scheduled_at IS 'Not NULL indicates a snapshot is in the process of being taken';


--
-- Name: command_types; Type: TABLE; Schema: sequent_schema; Owner: -
--

CREATE TABLE sequent_schema.command_types (
    id smallint NOT NULL,
    type text NOT NULL
);


--
-- Name: command_records; Type: VIEW; Schema: sequent_schema; Owner: -
--

CREATE VIEW sequent_schema.command_records AS
 SELECT id,
    user_id,
    aggregate_id,
    ( SELECT command_types.type
           FROM sequent_schema.command_types
          WHERE (command_types.id = command.command_type_id)) AS command_type,
    sequent_schema.enrich_command_json(command.*) AS command_json,
    created_at,
    event_aggregate_id,
    event_sequence_number
   FROM sequent_schema.commands command;


--
-- Name: command_types_id_seq; Type: SEQUENCE; Schema: sequent_schema; Owner: -
--

ALTER TABLE sequent_schema.command_types ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME sequent_schema.command_types_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: commands_default; Type: TABLE; Schema: sequent_schema; Owner: -
--

CREATE TABLE sequent_schema.commands_default (
    id bigint NOT NULL,
    created_at timestamp with time zone NOT NULL,
    user_id uuid,
    aggregate_id uuid,
    command_type_id smallint NOT NULL,
    command_json jsonb NOT NULL,
    event_aggregate_id uuid,
    event_sequence_number integer
);


--
-- Name: commands_id_seq; Type: SEQUENCE; Schema: sequent_schema; Owner: -
--

ALTER TABLE sequent_schema.commands ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME sequent_schema.commands_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: event_types; Type: TABLE; Schema: sequent_schema; Owner: -
--

CREATE TABLE sequent_schema.event_types (
    id smallint NOT NULL,
    type text NOT NULL
);


--
-- Name: event_records; Type: VIEW; Schema: sequent_schema; Owner: -
--

CREATE VIEW sequent_schema.event_records AS
 SELECT aggregate.aggregate_id,
    event.partition_key,
    event.sequence_number,
    event.created_at,
    type.type AS event_type,
    sequent_schema.enrich_event_json(event.*) AS event_json,
    event.command_id AS command_record_id,
    event.xact_id
   FROM ((sequent_schema.events event
     JOIN sequent_schema.aggregates aggregate ON (((aggregate.aggregate_id = event.aggregate_id) AND (aggregate.events_partition_key = event.partition_key))))
     JOIN sequent_schema.event_types type ON ((event.event_type_id = type.id)));


--
-- Name: event_types_id_seq; Type: SEQUENCE; Schema: sequent_schema; Owner: -
--

ALTER TABLE sequent_schema.event_types ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME sequent_schema.event_types_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: events_default; Type: TABLE; Schema: sequent_schema; Owner: -
--

CREATE TABLE sequent_schema.events_default (
    aggregate_id uuid NOT NULL,
    partition_key text DEFAULT ''::text NOT NULL,
    sequence_number integer NOT NULL,
    created_at timestamp with time zone NOT NULL,
    command_id bigint NOT NULL,
    event_type_id smallint NOT NULL,
    event_json jsonb NOT NULL,
    xact_id bigint DEFAULT ((pg_current_xact_id())::text)::bigint
);


--
-- Name: partition_key_changes; Type: TABLE; Schema: sequent_schema; Owner: -
--

CREATE TABLE sequent_schema.partition_key_changes (
    aggregate_id uuid NOT NULL,
    old_partition_key text NOT NULL,
    new_partition_key text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: projector_states; Type: TABLE; Schema: sequent_schema; Owner: -
--

CREATE TABLE sequent_schema.projector_states (
    name text NOT NULL,
    active_version integer,
    activating_version integer,
    replaying_version integer,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT activating_newer_than_active CHECK ((activating_version > active_version)),
    CONSTRAINT replaying_conflicts_with_activating CHECK (((replaying_version IS NULL) OR (activating_version IS NULL))),
    CONSTRAINT replaying_newer_then_active CHECK ((replaying_version > active_version))
);


--
-- Name: replay_states; Type: TABLE; Schema: sequent_schema; Owner: -
--

CREATE TABLE sequent_schema.replay_states (
    id bigint NOT NULL,
    state text NOT NULL,
    projectors text[] NOT NULL,
    continue_replay_at_xact_id bigint,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT valid_replay_state CHECK ((state = ANY (ARRAY['created'::text, 'prepared'::text, 'initial_replay'::text, 'incremental_replay'::text, 'ready_for_activation'::text, 'failed'::text, 'done'::text, 'aborted'::text])))
);


--
-- Name: replay_states_id_seq; Type: SEQUENCE; Schema: sequent_schema; Owner: -
--

CREATE SEQUENCE sequent_schema.replay_states_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: replay_states_id_seq; Type: SEQUENCE OWNED BY; Schema: sequent_schema; Owner: -
--

ALTER SEQUENCE sequent_schema.replay_states_id_seq OWNED BY sequent_schema.replay_states.id;


--
-- Name: saved_event_records; Type: TABLE; Schema: sequent_schema; Owner: -
--

CREATE TABLE sequent_schema.saved_event_records (
    operation character varying(1) NOT NULL,
    "timestamp" timestamp with time zone NOT NULL,
    "user" text NOT NULL,
    aggregate_id uuid NOT NULL,
    partition_key text DEFAULT ''::text,
    sequence_number integer NOT NULL,
    created_at timestamp with time zone NOT NULL,
    command_id bigint NOT NULL,
    event_type text NOT NULL,
    event_json jsonb NOT NULL,
    xact_id bigint,
    CONSTRAINT saved_event_records_operation_check CHECK (((operation)::text = ANY ((ARRAY['U'::character varying, 'D'::character varying])::text[])))
);


--
-- Name: snapshot_records; Type: TABLE; Schema: sequent_schema; Owner: -
--

CREATE TABLE sequent_schema.snapshot_records (
    aggregate_id uuid NOT NULL,
    sequence_number integer NOT NULL,
    created_at timestamp with time zone NOT NULL,
    snapshot_type text NOT NULL,
    snapshot_json jsonb NOT NULL,
    snapshot_version integer NOT NULL
);


--
-- Name: stream_records; Type: VIEW; Schema: sequent_schema; Owner: -
--

CREATE VIEW sequent_schema.stream_records AS
 SELECT aggregates.aggregate_id,
    aggregates.events_partition_key,
    aggregate_types.type AS aggregate_type,
    aggregates.created_at
   FROM (sequent_schema.aggregates
     JOIN sequent_schema.aggregate_types ON ((aggregates.aggregate_type_id = aggregate_types.id)));


--
-- Name: aggregates_default; Type: TABLE ATTACH; Schema: sequent_schema; Owner: -
--

ALTER TABLE ONLY sequent_schema.aggregates ATTACH PARTITION sequent_schema.aggregates_default DEFAULT;


--
-- Name: commands_default; Type: TABLE ATTACH; Schema: sequent_schema; Owner: -
--

ALTER TABLE ONLY sequent_schema.commands ATTACH PARTITION sequent_schema.commands_default DEFAULT;


--
-- Name: events_default; Type: TABLE ATTACH; Schema: sequent_schema; Owner: -
--

ALTER TABLE ONLY sequent_schema.events ATTACH PARTITION sequent_schema.events_default DEFAULT;


--
-- Name: replay_states id; Type: DEFAULT; Schema: sequent_schema; Owner: -
--

ALTER TABLE ONLY sequent_schema.replay_states ALTER COLUMN id SET DEFAULT nextval('sequent_schema.replay_states_id_seq'::regclass);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: aggregate_types aggregate_types_pkey; Type: CONSTRAINT; Schema: sequent_schema; Owner: -
--

ALTER TABLE ONLY sequent_schema.aggregate_types
    ADD CONSTRAINT aggregate_types_pkey PRIMARY KEY (id);


--
-- Name: aggregate_types aggregate_types_type_key; Type: CONSTRAINT; Schema: sequent_schema; Owner: -
--

ALTER TABLE ONLY sequent_schema.aggregate_types
    ADD CONSTRAINT aggregate_types_type_key UNIQUE (type);


--
-- Name: aggregate_unique_keys aggregate_unique_keys_pkey; Type: CONSTRAINT; Schema: sequent_schema; Owner: -
--

ALTER TABLE ONLY sequent_schema.aggregate_unique_keys
    ADD CONSTRAINT aggregate_unique_keys_pkey PRIMARY KEY (aggregate_id, scope);


--
-- Name: aggregate_unique_keys aggregate_unique_keys_scope_key_key; Type: CONSTRAINT; Schema: sequent_schema; Owner: -
--

ALTER TABLE ONLY sequent_schema.aggregate_unique_keys
    ADD CONSTRAINT aggregate_unique_keys_scope_key_key UNIQUE (scope, key);


--
-- Name: aggregates aggregates_events_partition_key_aggregate_id_key; Type: CONSTRAINT; Schema: sequent_schema; Owner: -
--

ALTER TABLE ONLY sequent_schema.aggregates
    ADD CONSTRAINT aggregates_events_partition_key_aggregate_id_key UNIQUE (events_partition_key, aggregate_id);


--
-- Name: aggregates_default aggregates_default_events_partition_key_aggregate_id_key; Type: CONSTRAINT; Schema: sequent_schema; Owner: -
--

ALTER TABLE ONLY sequent_schema.aggregates_default
    ADD CONSTRAINT aggregates_default_events_partition_key_aggregate_id_key UNIQUE (events_partition_key, aggregate_id);


--
-- Name: aggregates aggregates_pkey; Type: CONSTRAINT; Schema: sequent_schema; Owner: -
--

ALTER TABLE ONLY sequent_schema.aggregates
    ADD CONSTRAINT aggregates_pkey PRIMARY KEY (aggregate_id);


--
-- Name: aggregates_default aggregates_default_pkey; Type: CONSTRAINT; Schema: sequent_schema; Owner: -
--

ALTER TABLE ONLY sequent_schema.aggregates_default
    ADD CONSTRAINT aggregates_default_pkey PRIMARY KEY (aggregate_id);


--
-- Name: aggregates_that_need_snapshots aggregates_that_need_snapshots_pkey; Type: CONSTRAINT; Schema: sequent_schema; Owner: -
--

ALTER TABLE ONLY sequent_schema.aggregates_that_need_snapshots
    ADD CONSTRAINT aggregates_that_need_snapshots_pkey PRIMARY KEY (aggregate_id, snapshot_version);


--
-- Name: command_types command_types_pkey; Type: CONSTRAINT; Schema: sequent_schema; Owner: -
--

ALTER TABLE ONLY sequent_schema.command_types
    ADD CONSTRAINT command_types_pkey PRIMARY KEY (id);


--
-- Name: command_types command_types_type_key; Type: CONSTRAINT; Schema: sequent_schema; Owner: -
--

ALTER TABLE ONLY sequent_schema.command_types
    ADD CONSTRAINT command_types_type_key UNIQUE (type);


--
-- Name: commands commands_pkey; Type: CONSTRAINT; Schema: sequent_schema; Owner: -
--

ALTER TABLE ONLY sequent_schema.commands
    ADD CONSTRAINT commands_pkey PRIMARY KEY (id);


--
-- Name: commands_default commands_default_pkey; Type: CONSTRAINT; Schema: sequent_schema; Owner: -
--

ALTER TABLE ONLY sequent_schema.commands_default
    ADD CONSTRAINT commands_default_pkey PRIMARY KEY (id);


--
-- Name: event_types event_types_pkey; Type: CONSTRAINT; Schema: sequent_schema; Owner: -
--

ALTER TABLE ONLY sequent_schema.event_types
    ADD CONSTRAINT event_types_pkey PRIMARY KEY (id);


--
-- Name: event_types event_types_type_key; Type: CONSTRAINT; Schema: sequent_schema; Owner: -
--

ALTER TABLE ONLY sequent_schema.event_types
    ADD CONSTRAINT event_types_type_key UNIQUE (type);


--
-- Name: events events_pkey; Type: CONSTRAINT; Schema: sequent_schema; Owner: -
--

ALTER TABLE ONLY sequent_schema.events
    ADD CONSTRAINT events_pkey PRIMARY KEY (partition_key, aggregate_id, sequence_number);


--
-- Name: events_default events_default_pkey; Type: CONSTRAINT; Schema: sequent_schema; Owner: -
--

ALTER TABLE ONLY sequent_schema.events_default
    ADD CONSTRAINT events_default_pkey PRIMARY KEY (partition_key, aggregate_id, sequence_number);


--
-- Name: partition_key_changes partition_key_changes_pkey; Type: CONSTRAINT; Schema: sequent_schema; Owner: -
--

ALTER TABLE ONLY sequent_schema.partition_key_changes
    ADD CONSTRAINT partition_key_changes_pkey PRIMARY KEY (aggregate_id);


--
-- Name: projector_states projector_states_pkey; Type: CONSTRAINT; Schema: sequent_schema; Owner: -
--

ALTER TABLE ONLY sequent_schema.projector_states
    ADD CONSTRAINT projector_states_pkey PRIMARY KEY (name);


--
-- Name: replay_states replay_states_pkey; Type: CONSTRAINT; Schema: sequent_schema; Owner: -
--

ALTER TABLE ONLY sequent_schema.replay_states
    ADD CONSTRAINT replay_states_pkey PRIMARY KEY (id);


--
-- Name: saved_event_records saved_event_records_pkey; Type: CONSTRAINT; Schema: sequent_schema; Owner: -
--

ALTER TABLE ONLY sequent_schema.saved_event_records
    ADD CONSTRAINT saved_event_records_pkey PRIMARY KEY (aggregate_id, sequence_number, "timestamp");


--
-- Name: snapshot_records snapshot_records_pkey; Type: CONSTRAINT; Schema: sequent_schema; Owner: -
--

ALTER TABLE ONLY sequent_schema.snapshot_records
    ADD CONSTRAINT snapshot_records_pkey PRIMARY KEY (aggregate_id, snapshot_version, sequence_number);


--
-- Name: aggregates_aggregate_type_id_idx; Type: INDEX; Schema: sequent_schema; Owner: -
--

CREATE INDEX aggregates_aggregate_type_id_idx ON ONLY sequent_schema.aggregates USING btree (aggregate_type_id);


--
-- Name: aggregates_default_aggregate_type_id_idx; Type: INDEX; Schema: sequent_schema; Owner: -
--

CREATE INDEX aggregates_default_aggregate_type_id_idx ON sequent_schema.aggregates_default USING btree (aggregate_type_id);


--
-- Name: aggregates_that_need_snapshots_outdated_idx; Type: INDEX; Schema: sequent_schema; Owner: -
--

CREATE INDEX aggregates_that_need_snapshots_outdated_idx ON sequent_schema.aggregates_that_need_snapshots USING btree (snapshot_outdated_at, snapshot_sequence_number_high_water_mark DESC, aggregate_id) WHERE (snapshot_outdated_at IS NOT NULL);


--
-- Name: commands_aggregate_id_idx; Type: INDEX; Schema: sequent_schema; Owner: -
--

CREATE INDEX commands_aggregate_id_idx ON ONLY sequent_schema.commands USING btree (aggregate_id);


--
-- Name: commands_command_type_id_idx; Type: INDEX; Schema: sequent_schema; Owner: -
--

CREATE INDEX commands_command_type_id_idx ON ONLY sequent_schema.commands USING btree (command_type_id);


--
-- Name: commands_default_aggregate_id_idx; Type: INDEX; Schema: sequent_schema; Owner: -
--

CREATE INDEX commands_default_aggregate_id_idx ON sequent_schema.commands_default USING btree (aggregate_id);


--
-- Name: commands_default_command_type_id_idx; Type: INDEX; Schema: sequent_schema; Owner: -
--

CREATE INDEX commands_default_command_type_id_idx ON sequent_schema.commands_default USING btree (command_type_id);


--
-- Name: commands_event_idx; Type: INDEX; Schema: sequent_schema; Owner: -
--

CREATE INDEX commands_event_idx ON ONLY sequent_schema.commands USING btree (event_aggregate_id, event_sequence_number);


--
-- Name: commands_default_event_aggregate_id_event_sequence_number_idx; Type: INDEX; Schema: sequent_schema; Owner: -
--

CREATE INDEX commands_default_event_aggregate_id_event_sequence_number_idx ON sequent_schema.commands_default USING btree (event_aggregate_id, event_sequence_number);


--
-- Name: events_command_id_idx; Type: INDEX; Schema: sequent_schema; Owner: -
--

CREATE INDEX events_command_id_idx ON ONLY sequent_schema.events USING btree (command_id);


--
-- Name: events_default_command_id_idx; Type: INDEX; Schema: sequent_schema; Owner: -
--

CREATE INDEX events_default_command_id_idx ON sequent_schema.events_default USING btree (command_id);


--
-- Name: events_event_type_id_idx; Type: INDEX; Schema: sequent_schema; Owner: -
--

CREATE INDEX events_event_type_id_idx ON ONLY sequent_schema.events USING btree (event_type_id);


--
-- Name: events_default_event_type_id_idx; Type: INDEX; Schema: sequent_schema; Owner: -
--

CREATE INDEX events_default_event_type_id_idx ON sequent_schema.events_default USING btree (event_type_id);


--
-- Name: replay_states_active_replay_idx; Type: INDEX; Schema: sequent_schema; Owner: -
--

CREATE UNIQUE INDEX replay_states_active_replay_idx ON sequent_schema.replay_states USING btree ((true)) WHERE (state <> ALL (ARRAY['done'::text, 'aborted'::text]));


--
-- Name: aggregates_default_aggregate_type_id_idx; Type: INDEX ATTACH; Schema: sequent_schema; Owner: -
--

ALTER INDEX sequent_schema.aggregates_aggregate_type_id_idx ATTACH PARTITION sequent_schema.aggregates_default_aggregate_type_id_idx;


--
-- Name: aggregates_default_events_partition_key_aggregate_id_key; Type: INDEX ATTACH; Schema: sequent_schema; Owner: -
--

ALTER INDEX sequent_schema.aggregates_events_partition_key_aggregate_id_key ATTACH PARTITION sequent_schema.aggregates_default_events_partition_key_aggregate_id_key;


--
-- Name: aggregates_default_pkey; Type: INDEX ATTACH; Schema: sequent_schema; Owner: -
--

ALTER INDEX sequent_schema.aggregates_pkey ATTACH PARTITION sequent_schema.aggregates_default_pkey;


--
-- Name: commands_default_aggregate_id_idx; Type: INDEX ATTACH; Schema: sequent_schema; Owner: -
--

ALTER INDEX sequent_schema.commands_aggregate_id_idx ATTACH PARTITION sequent_schema.commands_default_aggregate_id_idx;


--
-- Name: commands_default_command_type_id_idx; Type: INDEX ATTACH; Schema: sequent_schema; Owner: -
--

ALTER INDEX sequent_schema.commands_command_type_id_idx ATTACH PARTITION sequent_schema.commands_default_command_type_id_idx;


--
-- Name: commands_default_event_aggregate_id_event_sequence_number_idx; Type: INDEX ATTACH; Schema: sequent_schema; Owner: -
--

ALTER INDEX sequent_schema.commands_event_idx ATTACH PARTITION sequent_schema.commands_default_event_aggregate_id_event_sequence_number_idx;


--
-- Name: commands_default_pkey; Type: INDEX ATTACH; Schema: sequent_schema; Owner: -
--

ALTER INDEX sequent_schema.commands_pkey ATTACH PARTITION sequent_schema.commands_default_pkey;


--
-- Name: events_default_command_id_idx; Type: INDEX ATTACH; Schema: sequent_schema; Owner: -
--

ALTER INDEX sequent_schema.events_command_id_idx ATTACH PARTITION sequent_schema.events_default_command_id_idx;


--
-- Name: events_default_event_type_id_idx; Type: INDEX ATTACH; Schema: sequent_schema; Owner: -
--

ALTER INDEX sequent_schema.events_event_type_id_idx ATTACH PARTITION sequent_schema.events_default_event_type_id_idx;


--
-- Name: events_default_pkey; Type: INDEX ATTACH; Schema: sequent_schema; Owner: -
--

ALTER INDEX sequent_schema.events_pkey ATTACH PARTITION sequent_schema.events_default_pkey;


--
-- Name: events save_events_on_delete_trigger; Type: TRIGGER; Schema: sequent_schema; Owner: -
--

CREATE TRIGGER save_events_on_delete_trigger AFTER DELETE ON sequent_schema.events REFERENCING OLD TABLE AS old_table FOR EACH STATEMENT EXECUTE FUNCTION sequent_schema.save_events_on_delete_trigger();


--
-- Name: events save_events_on_update_trigger; Type: TRIGGER; Schema: sequent_schema; Owner: -
--

CREATE TRIGGER save_events_on_update_trigger AFTER UPDATE ON sequent_schema.events REFERENCING OLD TABLE AS old_table NEW TABLE AS new_table FOR EACH STATEMENT EXECUTE FUNCTION sequent_schema.save_events_on_update_trigger();


--
-- Name: partition_key_changes aggregate_fk; Type: FK CONSTRAINT; Schema: sequent_schema; Owner: -
--

ALTER TABLE ONLY sequent_schema.partition_key_changes
    ADD CONSTRAINT aggregate_fk FOREIGN KEY (aggregate_id) REFERENCES sequent_schema.aggregates(aggregate_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: aggregate_unique_keys aggregate_unique_keys_aggregate_id_fkey; Type: FK CONSTRAINT; Schema: sequent_schema; Owner: -
--

ALTER TABLE ONLY sequent_schema.aggregate_unique_keys
    ADD CONSTRAINT aggregate_unique_keys_aggregate_id_fkey FOREIGN KEY (aggregate_id) REFERENCES sequent_schema.aggregates(aggregate_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: aggregates aggregates_aggregate_type_id_fkey; Type: FK CONSTRAINT; Schema: sequent_schema; Owner: -
--

ALTER TABLE sequent_schema.aggregates
    ADD CONSTRAINT aggregates_aggregate_type_id_fkey FOREIGN KEY (aggregate_type_id) REFERENCES sequent_schema.aggregate_types(id) ON UPDATE CASCADE;


--
-- Name: aggregates_that_need_snapshots aggregates_that_need_snapshots_aggregate_id_fkey; Type: FK CONSTRAINT; Schema: sequent_schema; Owner: -
--

ALTER TABLE ONLY sequent_schema.aggregates_that_need_snapshots
    ADD CONSTRAINT aggregates_that_need_snapshots_aggregate_id_fkey FOREIGN KEY (aggregate_id) REFERENCES sequent_schema.aggregates(aggregate_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: commands commands_command_type_id_fkey; Type: FK CONSTRAINT; Schema: sequent_schema; Owner: -
--

ALTER TABLE sequent_schema.commands
    ADD CONSTRAINT commands_command_type_id_fkey FOREIGN KEY (command_type_id) REFERENCES sequent_schema.command_types(id) ON UPDATE CASCADE;


--
-- Name: events events_command_id_fkey; Type: FK CONSTRAINT; Schema: sequent_schema; Owner: -
--

ALTER TABLE sequent_schema.events
    ADD CONSTRAINT events_command_id_fkey FOREIGN KEY (command_id) REFERENCES sequent_schema.commands(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: events events_event_type_id_fkey; Type: FK CONSTRAINT; Schema: sequent_schema; Owner: -
--

ALTER TABLE sequent_schema.events
    ADD CONSTRAINT events_event_type_id_fkey FOREIGN KEY (event_type_id) REFERENCES sequent_schema.event_types(id) ON UPDATE CASCADE;


--
-- Name: events events_partition_key_aggregate_id_fkey; Type: FK CONSTRAINT; Schema: sequent_schema; Owner: -
--

ALTER TABLE sequent_schema.events
    ADD CONSTRAINT events_partition_key_aggregate_id_fkey FOREIGN KEY (partition_key, aggregate_id) REFERENCES sequent_schema.aggregates(events_partition_key, aggregate_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: snapshot_records snapshot_records_aggregate_id_snapshot_version_fkey; Type: FK CONSTRAINT; Schema: sequent_schema; Owner: -
--

ALTER TABLE ONLY sequent_schema.snapshot_records
    ADD CONSTRAINT snapshot_records_aggregate_id_snapshot_version_fkey FOREIGN KEY (aggregate_id, snapshot_version) REFERENCES sequent_schema.aggregates_that_need_snapshots(aggregate_id, snapshot_version) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

SET search_path TO public,view_schema,sequent_schema;

INSERT INTO "schema_migrations" (version) VALUES
('20250630113000'),
('20250601120000'),
('20250512135500'),
('20250509133000'),
('20250509120000'),
('20250501120000'),
('20250312105100'),
('20250101000001'),
('20250101000000');

