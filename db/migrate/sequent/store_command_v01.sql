CREATE OR REPLACE FUNCTION store_command(_command jsonb) RETURNS bigint RETURNS NULL ON NULL INPUT
LANGUAGE plpgsql SET search_path FROM CURRENT AS $$
DECLARE
  _id commands.id%TYPE;
  _command_json jsonb = _command->'command_json';
BEGIN
  INSERT INTO commands (
    created_at, user_id, aggregate_id, command_type_id, command_json,
    event_aggregate_id, event_sequence_number
  ) VALUES (
    (_command->>'created_at')::timestamptz,
    (_command_json->>'user_id')::uuid,
    (_command_json->>'aggregate_id')::uuid,
    (SELECT id FROM command_types WHERE type = _command->>'command_type'),
    (_command->'command_json') - '{command_type,created_at,user_id,aggregate_id,event_aggregate_id,event_sequence_number}'::text[],
    (_command_json->>'event_aggregate_id')::uuid,
    NULLIF(_command_json->'event_sequence_number', 'null'::jsonb)::integer
  ) RETURNING id INTO STRICT _id;
  RETURN _id;
END;
$$;
