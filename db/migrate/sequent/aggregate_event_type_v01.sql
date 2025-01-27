CREATE TYPE aggregate_event_type AS (
  aggregate_type text,
  aggregate_id uuid,
  events_partition_key text,
  event_type text,
  event_json jsonb
);
