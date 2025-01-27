DROP VIEW IF EXISTS event_records;
CREATE VIEW event_records (aggregate_id, partition_key, sequence_number, created_at, event_type, event_json, command_record_id, xact_id) AS
     SELECT aggregate.aggregate_id,
            event.partition_key,
            event.sequence_number,
            event.created_at,
            type.type,
            enrich_event_json(event) AS event_json,
            command_id,
            event.xact_id
       FROM events event
       JOIN aggregates aggregate ON aggregate.aggregate_id = event.aggregate_id AND aggregate.events_partition_key = event.partition_key
       JOIN event_types type ON event.event_type_id = type.id;
