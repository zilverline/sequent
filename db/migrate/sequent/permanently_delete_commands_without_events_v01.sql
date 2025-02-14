DROP PROCEDURE IF EXISTS permanently_delete_commands_without_events(uuid, uuid);
CREATE OR REPLACE PROCEDURE permanently_delete_commands_without_events(_aggregate_id uuid)
LANGUAGE plpgsql SET search_path FROM CURRENT AS $$
BEGIN
  IF _aggregate_id IS NULL THEN
    RAISE EXCEPTION 'aggregate_id must be specified to delete commands';
  END IF;

  DELETE FROM commands
   WHERE aggregate_id = _aggregate_id
     AND NOT EXISTS (SELECT 1 FROM events WHERE command_id = commands.id);
END;
$$;
