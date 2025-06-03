DROP TYPE IF EXISTS aggregate_event_type CASCADE;
CREATE TYPE aggregate_event_type AS (
  aggregate_type text,
  aggregate_id uuid,
  events_partition_key text,
  event_sequence_number integer,
  event_type text,
  event_json jsonb
);
