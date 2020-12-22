CREATE TABLE item_records%SUFFIX% (
    id serial NOT NULL,
    aggregate_id uuid NOT NULL,
    CONSTRAINT item_records_pkey%SUFFIX% PRIMARY KEY (id)
);

CREATE INDEX aggregate_id%SUFFIX% ON item_records%SUFFIX% USING btree (aggregate_id);
