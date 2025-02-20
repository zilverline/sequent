CREATE OR REPLACE FUNCTION enrich_command_json(command commands) RETURNS jsonb RETURNS NULL ON NULL INPUT
LANGUAGE plpgsql SET search_path FROM CURRENT AS $$
BEGIN
  RETURN jsonb_build_object(
      'command_type', (SELECT type FROM command_types WHERE command_types.id = command.command_type_id),
      'created_at', command.created_at,
      'user_id', command.user_id,
      'aggregate_id', command.aggregate_id,
      'event_aggregate_id', command.event_aggregate_id,
      'event_sequence_number', command.event_sequence_number
    )
    || command.command_json;
END
$$;
