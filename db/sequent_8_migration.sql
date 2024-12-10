-- This script migrates a pre-sequent 8 database to the sequent 8 schema while preserving the data.
-- It runs in a single transaction and when completed you can COMMIT or ROLLBACK the results.
--
-- To adjust the partitioning setup you can modify `./sequent_schema_partitions.sql`. By default
-- only a single partition is present for each partitioned table, which works well for smaller
-- (e.g. less than 10 Gigabytes) databases.
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

ALTER SEQUENCE command_records_id_seq OWNED BY NONE;
ALTER SEQUENCE command_records_id_seq RENAME TO commands_id_seq;

\ir ./sequent_schema_tables.sql
\ir ./sequent_schema_partitions.sql

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

INSERT INTO aggregates (aggregate_id, aggregate_type_id, snapshot_threshold, created_at)
SELECT aggregate_id, (SELECT t.id FROM aggregate_types t WHERE aggregate_type = t.type), snapshot_threshold, created_at AT TIME ZONE 'Europe/Amsterdam'
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

INSERT INTO aggregates_that_need_snapshots (aggregate_id, snapshot_sequence_number_high_water_mark, snapshot_outdated_at)
SELECT aggregate_id, MAX(sequence_number), NOW()
  FROM event_records
 WHERE event_type = 'Sequent::Core::SnapshotEvent'
 GROUP BY 1
 ORDER BY 1;

ALTER TABLE command_records RENAME TO old_command_records;
ALTER TABLE event_records RENAME TO old_event_records;
ALTER TABLE stream_records RENAME TO old_stream_records;

\ir ./sequent_schema_indexes.sql

\set ECHO none

\ir ./sequent_pgsql.sql

\set ECHO all

SELECT clock_timestamp() AS migration_completed_at,
       clock_timestamp() - :'migration_started_at'::timestamptz AS migration_duration \gset

\echo Migration complated in :migration_duration (started at :migration_started_at, completed at :migration_completed_at)

\echo execute ROLLBACK to abort, COMMIT to commit followed by VACUUM VERBOSE ANALYZE to ensure good performance
