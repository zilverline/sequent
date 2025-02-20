DROP VIEW IF EXISTS stream_records;
CREATE VIEW stream_records (aggregate_id, events_partition_key, aggregate_type, created_at) AS
     SELECT aggregates.aggregate_id,
            aggregates.events_partition_key,
            aggregate_types.type,
            aggregates.created_at
       FROM aggregates JOIN aggregate_types ON aggregates.aggregate_type_id = aggregate_types.id;
