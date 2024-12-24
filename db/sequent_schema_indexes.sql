ALTER TABLE aggregates ADD PRIMARY KEY (aggregate_id);
ALTER TABLE aggregates ADD UNIQUE (events_partition_key, aggregate_id);
CREATE INDEX aggregates_aggregate_type_id_idx ON aggregates (aggregate_type_id);

ALTER TABLE commands ADD PRIMARY KEY (id);
CREATE INDEX commands_command_type_id_idx ON commands (command_type_id);
CREATE INDEX commands_aggregate_id_idx ON commands (aggregate_id);
CREATE INDEX commands_event_idx ON commands (event_aggregate_id, event_sequence_number);

ALTER TABLE events ADD PRIMARY KEY (partition_key, aggregate_id, sequence_number);
CREATE INDEX events_command_id_idx ON events (command_id);
CREATE INDEX events_event_type_id_idx ON events (event_type_id);

ALTER TABLE aggregates
  ADD FOREIGN KEY (aggregate_type_id) REFERENCES aggregate_types (id) ON UPDATE CASCADE;

ALTER TABLE aggregate_unique_keys
  ADD PRIMARY KEY (aggregate_id, scope),
  ADD UNIQUE (scope, key),
  ADD FOREIGN KEY (aggregate_id) REFERENCES aggregates (aggregate_id) ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE events
  ADD FOREIGN KEY (partition_key, aggregate_id) REFERENCES aggregates (events_partition_key, aggregate_id)
          ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE events
  ADD FOREIGN KEY (command_id) REFERENCES commands (id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE events
  ADD FOREIGN KEY (event_type_id) REFERENCES event_types (id) ON UPDATE CASCADE;
ALTER TABLE events ALTER COLUMN xact_id SET DEFAULT pg_current_xact_id()::text::bigint;

ALTER TABLE commands
  ADD FOREIGN KEY (command_type_id) REFERENCES command_types (id) ON UPDATE CASCADE;

ALTER TABLE aggregates_that_need_snapshots
  ADD FOREIGN KEY (aggregate_id) REFERENCES aggregates (aggregate_id) ON UPDATE CASCADE ON DELETE CASCADE;

CREATE INDEX aggregates_that_need_snapshots_outdated_idx
          ON aggregates_that_need_snapshots (snapshot_outdated_at ASC, snapshot_sequence_number_high_water_mark DESC, aggregate_id ASC)
       WHERE snapshot_outdated_at IS NOT NULL;

ALTER TABLE snapshot_records
  ADD FOREIGN KEY (aggregate_id) REFERENCES aggregates_that_need_snapshots (aggregate_id) ON UPDATE CASCADE ON DELETE CASCADE;
