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

CREATE TABLE snapshot_records (
  aggregate_id uuid NOT NULL,
  sequence_number integer NOT NULL,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  snapshot_type text NOT NULL,
  snapshot_json jsonb NOT NULL,
  PRIMARY KEY (aggregate_id, sequence_number),
  FOREIGN KEY (aggregate_id) REFERENCES aggregates (aggregate_id)
    ON UPDATE CASCADE ON DELETE CASCADE
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

CREATE TABLE aggregates_that_need_snapshots (
  aggregate_id uuid NOT NULL PRIMARY KEY REFERENCES aggregates (aggregate_id) ON UPDATE CASCADE ON DELETE CASCADE,
  snapshot_outdated_at timestamp with time zone,
  snapshot_sequence_number_high_water_mark integer
);
CREATE INDEX aggregates_that_need_snapshots_outdated_idx
          ON aggregates_that_need_snapshots (snapshot_outdated_at ASC, snapshot_sequence_number_high_water_mark DESC, aggregate_id ASC)
       WHERE snapshot_outdated_at IS NOT NULL;
COMMENT ON TABLE aggregates_that_need_snapshots IS 'Contains a row for every aggregate with more events than its snapshot threshold.';
COMMENT ON COLUMN aggregates_that_need_snapshots.snapshot_outdated_at IS 'Not NULL indicates a snapshot is needed since the stored timestamp';
COMMENT ON COLUMN aggregates_that_need_snapshots.snapshot_sequence_number_high_water_mark
  IS 'The highest sequence number of the stored snapshot. Kept when snapshot are deleted to more easily query aggregates that need snapshotting the most';
