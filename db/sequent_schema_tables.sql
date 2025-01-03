CREATE TABLE command_types (id SMALLINT PRIMARY KEY, type text UNIQUE NOT NULL);
CREATE TABLE aggregate_types (id SMALLINT PRIMARY KEY, type text UNIQUE NOT NULL);
CREATE TABLE event_types (id SMALLINT PRIMARY KEY, type text UNIQUE NOT NULL);

CREATE SEQUENCE IF NOT EXISTS commands_id_seq;

CREATE TABLE commands (
    id bigint NOT NULL DEFAULT nextval('commands_id_seq'),
    created_at timestamp with time zone NOT NULL,
    user_id uuid,
    aggregate_id uuid,
    command_type_id SMALLINT NOT NULL,
    command_json jsonb NOT NULL,
    event_aggregate_id uuid,
    event_sequence_number integer
) PARTITION BY RANGE (id);

ALTER SEQUENCE commands_id_seq OWNED BY commands.id;

CREATE TABLE aggregates (
    aggregate_id uuid NOT NULL,
    events_partition_key text NOT NULL DEFAULT '',
    aggregate_type_id SMALLINT NOT NULL,
    snapshot_threshold integer,
    created_at timestamp with time zone NOT NULL DEFAULT NOW()
) PARTITION BY RANGE (aggregate_id);

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

CREATE TABLE aggregates_that_need_snapshots (
  aggregate_id uuid NOT NULL PRIMARY KEY,
  snapshot_sequence_number_high_water_mark integer,
  snapshot_outdated_at timestamp with time zone,
  snapshot_scheduled_at timestamp with time zone
);

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
  PRIMARY KEY (aggregate_id, sequence_number)
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
