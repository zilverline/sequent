DROP VIEW IF EXISTS command_records;
CREATE VIEW command_records (id, user_id, aggregate_id, command_type, command_json, created_at, event_aggregate_id, event_sequence_number) AS
  SELECT id,
         user_id,
         aggregate_id,
         (SELECT type FROM command_types WHERE command_types.id = command.command_type_id),
         enrich_command_json(command),
         created_at,
         event_aggregate_id,
         event_sequence_number
    FROM commands command;
