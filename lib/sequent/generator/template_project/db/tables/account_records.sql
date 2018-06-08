CREATE TABLE account_records%SUFFIX% (
    id serial NOT NULL,
    aggregate_id uuid NOT NULL,
    name character varying,
    CONSTRAINT account_records_pkey%SUFFIX% PRIMARY KEY (id)
);

CREATE UNIQUE INDEX account_records_keys%SUFFIX% ON account_records%SUFFIX% USING btree (aggregate_id);
