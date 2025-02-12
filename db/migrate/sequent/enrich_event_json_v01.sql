CREATE OR REPLACE FUNCTION enrich_event_json(event events) RETURNS jsonb RETURNS NULL ON NULL INPUT
LANGUAGE plpgsql SET search_path FROM CURRENT AS $$
BEGIN
  RETURN jsonb_build_object(
      'aggregate_id', event.aggregate_id,
      'sequence_number', event.sequence_number,
      'created_at', event.created_at
    )
    || event.event_json;
END
$$;
