CREATE OR REPLACE FUNCTION save_events_on_delete_trigger() RETURNS TRIGGER
LANGUAGE plpgsql SET search_path FROM CURRENT AS $$
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

CREATE OR REPLACE FUNCTION save_events_on_update_trigger() RETURNS TRIGGER
LANGUAGE plpgsql SET search_path FROM CURRENT AS $$
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

CREATE OR REPLACE TRIGGER save_events_on_delete_trigger
    AFTER DELETE ON events
    REFERENCING OLD TABLE AS old_table
    FOR EACH STATEMENT EXECUTE FUNCTION save_events_on_delete_trigger();
CREATE OR REPLACE TRIGGER save_events_on_update_trigger
    AFTER UPDATE ON events
    REFERENCING OLD TABLE AS old_table NEW TABLE AS new_table
    FOR EACH STATEMENT EXECUTE FUNCTION save_events_on_update_trigger();
