CREATE OR REPLACE PROCEDURE update_unique_keys(_stream_records jsonb)
LANGUAGE plpgsql SET search_path FROM CURRENT AS $$
DECLARE
  _aggregate jsonb;
  _aggregate_id aggregates.aggregate_id%TYPE;
  _unique_keys jsonb;
BEGIN
  FOR _aggregate IN SELECT aggregate FROM jsonb_array_elements(_stream_records) AS aggregate LOOP
    _aggregate_id = _aggregate->>'aggregate_id';
    _unique_keys = COALESCE(_aggregate->'unique_keys', '{}'::jsonb);

    DELETE FROM aggregate_unique_keys AS target
     WHERE target.aggregate_id = _aggregate_id
       AND NOT (_unique_keys ? target.scope);
  END LOOP;

  FOR _aggregate IN SELECT aggregate FROM jsonb_array_elements(_stream_records) AS aggregate LOOP
    _aggregate_id = _aggregate->>'aggregate_id';
    _unique_keys = COALESCE(_aggregate->'unique_keys', '{}'::jsonb);

    INSERT INTO aggregate_unique_keys AS target (aggregate_id, scope, key)
    SELECT _aggregate_id, key, value
      FROM jsonb_each(_unique_keys) AS x
        ON CONFLICT (aggregate_id, scope) DO UPDATE
       SET key = EXCLUDED.key
     WHERE target.key <> EXCLUDED.key;
  END LOOP;
EXCEPTION
  WHEN unique_violation THEN
    RAISE unique_violation
    USING MESSAGE = 'duplicate unique key value for aggregate ' || (_aggregate->>'aggregate_type') || ' ' || _aggregate_id || ' (' || SQLERRM || ')';
END;
$$;
