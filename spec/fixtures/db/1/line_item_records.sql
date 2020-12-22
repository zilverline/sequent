CREATE TABLE line_item_records%SUFFIX% (
    id serial NOT NULL,
    item_aggregate_id uuid NOT NULL,
    CONSTRAINT line_item_records_pkey%SUFFIX% PRIMARY KEY (id)
);

CREATE INDEX aggregate_id%SUFFIX% ON line_item_records%SUFFIX% USING btree (item_aggregate_id);
