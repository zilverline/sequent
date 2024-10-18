-- This script migrates a pre-sequent 8 database to the sequent 8 schema while preserving the data.
-- It runs in a single transaction and when completed you can COMMIT or ROLLBACK the results.
--
-- Adjust this script to your needs (number of table partitions, etc). See comments marked with ###
-- for configuration sections.
--
-- Ensure you test this on a copy of your production system to verify everything works and to
-- get an indication of the required downtime for your system.

\set ECHO all
\set ON_ERROR_STOP
\timing on

SELECT clock_timestamp() AS migration_started_at \gset

\echo Migration started at :migration_started_at

SET work_mem TO '8MB';
SET max_parallel_workers = 8;
SET max_parallel_workers_per_gather = 8;
SET max_parallel_maintenance_workers = 8;

BEGIN;

SET temp_tablespaces = 'pg_default';
SET search_path TO sequent_schema;

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
    id bigint NOT NULL DEFAULT nextval('sequent_schema.command_records_id_seq'),
    created_at timestamp with time zone NOT NULL,
    user_id uuid,
    aggregate_id uuid,
    command_type_id SMALLINT NOT NULL,
    command_json jsonb NOT NULL,
    event_aggregate_id uuid,
    event_sequence_number integer
) PARTITION BY RANGE (id);

-- ### Configure partitions as needed
CREATE TABLE commands_default PARTITION OF commands DEFAULT;
CREATE TABLE commands_0 PARTITION OF commands FOR VALUES FROM (1) TO (100e6);
-- CREATE TABLE commands_1 PARTITION OF commands FOR VALUES FROM (100e6) TO (200e6);
-- CREATE TABLE commands_2 PARTITION OF commands FOR VALUES FROM (200e6) TO (300e6);
-- CREATE TABLE commands_3 PARTITION OF commands FOR VALUES FROM (300e6) TO (400e6);

CREATE TABLE aggregates (
    aggregate_id uuid NOT NULL,
    events_partition_key text NOT NULL DEFAULT '',
    aggregate_type_id SMALLINT NOT NULL,
    snapshot_threshold integer,
    created_at timestamp with time zone NOT NULL DEFAULT NOW()
) PARTITION BY RANGE (aggregate_id);

-- ### Configure partitions as needed
CREATE TABLE aggregates_0 PARTITION OF aggregates FOR VALUES FROM (MINVALUE) TO ('40000000-0000-0000-0000-000000000000');
CREATE TABLE aggregates_4 PARTITION OF aggregates FOR VALUES FROM ('40000000-0000-0000-0000-000000000000') TO ('80000000-0000-0000-0000-000000000000');
CREATE TABLE aggregates_8 PARTITION OF aggregates FOR VALUES FROM ('80000000-0000-0000-0000-000000000000') TO ('c0000000-0000-0000-0000-000000000000');
CREATE TABLE aggregates_c PARTITION OF aggregates FOR VALUES FROM ('c0000000-0000-0000-0000-000000000000') TO (MAXVALUE);

CREATE TABLE events (
  aggregate_id uuid NOT NULL,
  partition_key text NOT NULL DEFAULT '',
  sequence_number integer NOT NULL,
  created_at timestamp with time zone NOT NULL,
  command_id bigint NOT NULL,
  event_type_id SMALLINT NOT NULL,
  event_json jsonb NOT NULL,
  xact_id bigint
) PARTITION BY RANGE (partition_key);

CREATE INDEX events_xact_id_idx ON events (xact_id) WHERE xact_id IS NOT NULL;

-- ### Configure partitions as needed
CREATE TABLE events_default PARTITION OF events DEFAULT;
CREATE TABLE events_2023_and_earlier PARTITION OF events FOR VALUES FROM ('Y00') TO ('Y24');
CREATE TABLE events_2024 PARTITION OF events FOR VALUES FROM ('Y24') TO ('Y25');
CREATE TABLE events_2025_and_later PARTITION OF events FOR VALUES FROM ('Y25') TO ('Y99');
CREATE TABLE events_aggregate PARTITION OF events FOR VALUES FROM ('A') TO ('Ag');

INSERT INTO aggregate_types (type)
SELECT DISTINCT aggregate_type
  FROM sequent_schema.stream_records
 ORDER BY 1;

INSERT INTO event_types (type)
SELECT DISTINCT event_type
  FROM sequent_schema.event_records
 WHERE event_type <> 'Sequent::Core::SnapshotEvent'
 ORDER BY 1;

INSERT INTO command_types (type)
SELECT DISTINCT command_type
  FROM sequent_schema.command_records
 ORDER BY 1;

ANALYZE aggregate_types, event_types, command_types;

INSERT INTO aggregates
SELECT aggregate_id, '', (SELECT t.id FROM aggregate_types t WHERE aggregate_type = t.type), snapshot_threshold, created_at AT TIME ZONE 'Europe/Amsterdam'
  FROM stream_records;

WITH e AS MATERIALIZED (
  SELECT aggregate_id,
         sequence_number,
         command_record_id,
         t.id AS event_type_id,
         event_json::jsonb - '{aggregate_id,sequence_number}'::text[] AS event_json
    FROM sequent_schema.event_records e
    JOIN event_types t ON e.event_type = t.type
)
INSERT INTO events (aggregate_id, sequence_number, created_at, command_id, event_type_id, event_json)
SELECT aggregate_id,
       sequence_number,
       (event_json->>'created_at')::timestamptz AS created_at,
       command_record_id,
       event_type_id,
       event_json - 'created_at'
  FROM e;


WITH command AS MATERIALIZED (
  SELECT c.id, created_at,
         t.id AS command_type_id,
         command_json::jsonb AS json
    FROM sequent_schema.command_records c
    JOIN command_types t ON t.type = c.command_type
)
INSERT INTO commands (
  id, created_at, user_id, aggregate_id, command_type_id, command_json,
  event_aggregate_id, event_sequence_number
)
SELECT id,
       COALESCE((json->>'created_at')::timestamptz, created_at AT TIME ZONE 'Europe/Amsterdam'),
       (json->>'user_id')::uuid,
       (json->>'aggregate_id')::uuid,
       command_type_id,
       json - '{created_at,user_id,aggregate_id,event_aggregate_id,event_sequence_number}'::text[],
       (json->>'event_aggregate_id')::uuid,
       (json->>'event_sequence_number')::integer
  FROM command;

ALTER TABLE aggregates ADD UNIQUE (events_partition_key, aggregate_id);
-- ### Configure clustering as needed
ALTER TABLE aggregates_0 CLUSTER ON aggregates_0_events_partition_key_aggregate_id_key;
ALTER TABLE aggregates_4 CLUSTER ON aggregates_4_events_partition_key_aggregate_id_key;
ALTER TABLE aggregates_8 CLUSTER ON aggregates_8_events_partition_key_aggregate_id_key;
ALTER TABLE aggregates_c CLUSTER ON aggregates_c_events_partition_key_aggregate_id_key;

ALTER TABLE events
  ADD PRIMARY KEY (partition_key, aggregate_id, sequence_number);
-- ### Configure clustering as needed
ALTER TABLE events_default CLUSTER ON events_default_pkey;
ALTER TABLE events_2023_and_earlier CLUSTER ON events_2023_and_earlier_pkey;
ALTER TABLE events_2024 CLUSTER ON events_2024_pkey;
ALTER TABLE events_2025_and_later CLUSTER ON events_2025_and_later_pkey;
ALTER TABLE events_aggregate CLUSTER ON events_aggregate_pkey;

ALTER TABLE commands ADD PRIMARY KEY (id);

ALTER TABLE aggregates ADD PRIMARY KEY (aggregate_id);
CREATE INDEX aggregates_aggregate_type_id_idx ON aggregates (aggregate_type_id);
ALTER TABLE aggregates
  ADD FOREIGN KEY (aggregate_type_id) REFERENCES aggregate_types (id) ON UPDATE CASCADE;

CREATE INDEX events_command_id_idx ON events (command_id);
CREATE INDEX events_event_type_id_idx ON events (event_type_id);
ALTER TABLE events
  ADD FOREIGN KEY (partition_key, aggregate_id) REFERENCES aggregates (events_partition_key, aggregate_id)
          ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE events
  ADD FOREIGN KEY (command_id) REFERENCES commands (id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE events
  ADD FOREIGN KEY (event_type_id) REFERENCES event_types (id) ON UPDATE CASCADE;
ALTER TABLE events ALTER COLUMN xact_id SET DEFAULT pg_current_xact_id()::text::bigint;

CREATE INDEX commands_command_type_id_idx ON commands (command_type_id);
CREATE INDEX commands_aggregate_id_idx ON commands (aggregate_id);
CREATE INDEX commands_event_idx ON commands (event_aggregate_id, event_sequence_number);
ALTER TABLE commands
  ADD FOREIGN KEY (command_type_id) REFERENCES command_types (id) ON UPDATE CASCADE;

CREATE TABLE aggregates_that_need_snapshots (
  aggregate_id uuid NOT NULL PRIMARY KEY REFERENCES aggregates (aggregate_id) ON UPDATE CASCADE ON DELETE CASCADE,
  snapshot_sequence_number_high_water_mark integer,
  snapshot_outdated_at timestamp with time zone,
  snapshot_scheduled_at timestamp with time zone
);
INSERT INTO aggregates_that_need_snapshots (aggregate_id, snapshot_sequence_number_high_water_mark, snapshot_outdated_at)
SELECT aggregate_id, MAX(sequence_number), NOW()
  FROM event_records
 WHERE event_type = 'Sequent::Core::SnapshotEvent'
 GROUP BY 1
 ORDER BY 1;

CREATE INDEX aggregates_that_need_snapshots_outdated_idx
          ON aggregates_that_need_snapshots (snapshot_outdated_at ASC, snapshot_sequence_number_high_water_mark DESC, aggregate_id ASC)
       WHERE snapshot_outdated_at IS NOT NULL;
COMMENT ON TABLE aggregates_that_need_snapshots IS 'Contains a row for every aggregate with more events than its snapshot threshold.';
COMMENT ON COLUMN aggregates_that_need_snapshots.snapshot_sequence_number_high_water_mark
  IS 'The highest sequence number of the stored snapshot. Kept when snapshot are deleted to more easily query aggregates that need snapshotting the most';
COMMENT ON COLUMN aggregates_that_need_snapshots.snapshot_outdated_at IS 'Not NULL indicates a snapshot is needed since the stored timestamp';
COMMENT ON COLUMN aggregates_that_need_snapshots.snapshot_scheduled_at IS 'Not NULL indicates a snapshot is in the process of being taken';

CREATE TABLE snapshot_records (
  aggregate_id uuid NOT NULL,
  sequence_number integer NOT NULL,
  created_at timestamptz NOT NULL,
  snapshot_type text NOT NULL,
  snapshot_json jsonb NOT NULL,
  PRIMARY KEY (aggregate_id, sequence_number),
  FOREIGN KEY (aggregate_id) REFERENCES aggregates (aggregate_id) ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE saved_event_records (
  operation varchar(1) NOT NULL CHECK (operation IN ('U', 'D')),
  timestamp timestamptz NOT NULL,
  "user" text NOT NULL,
  aggregate_id uuid NOT NULL,
  partition_key text DEFAULT '',
  sequence_number integer NOT NULL,
  created_at timestamp with time zone NOT NULL,
  command_id bigint NOT NULL,
  event_type text NOT NULL,
  event_json jsonb NOT NULL,
  xact_id bigint,
  PRIMARY KEY (aggregate_id, sequence_number, timestamp)
);

ALTER SEQUENCE command_records_id_seq OWNED BY NONE;
ALTER SEQUENCE command_records_id_seq OWNED BY commands.id;
ALTER SEQUENCE command_records_id_seq RENAME TO commands_id_seq;

ALTER TABLE command_records RENAME TO old_command_records;
ALTER TABLE event_records RENAME TO old_event_records;
ALTER TABLE stream_records RENAME TO old_stream_records;

\set ECHO none

\ir ./sequent_pgsql.sql

\set ECHO all

SELECT clock_timestamp() AS migration_completed_at,
       clock_timestamp() - :'migration_started_at'::timestamptz AS migration_duration \gset

\echo Migration complated in :migration_duration (started at :migration_started_at, completed at :migration_completed_at)

\echo execute ROLLBACK to abort, COMMIT to commit followed by VACUUM VERBOSE ANALYZE to ensure good performance
