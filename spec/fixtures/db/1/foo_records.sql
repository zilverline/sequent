CREATE TABLE foo_records%SUFFIX% (
    id serial NOT NULL,
    aggregate_id uuid NOT NULL,
    type character varying NOT NULL,
    description text,
    CONSTRAINT foo_records_pkey%SUFFIX% PRIMARY KEY (id)
);

CREATE UNIQUE INDEX unique_foo_id%SUFFIX% ON foo_records%SUFFIX% USING btree (aggregate_id);
