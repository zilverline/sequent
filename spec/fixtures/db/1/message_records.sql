CREATE TABLE message_records%SUFFIX% (
    id serial NOT NULL,
    aggregate_id uuid NOT NULL,
    message text,
    CONSTRAINT message_records_pkey%SUFFIX% PRIMARY KEY (id)
);

CREATE UNIQUE INDEX unique_message_records_aggregate_id%SUFFIX% ON message_records%SUFFIX% USING btree (aggregate_id);
