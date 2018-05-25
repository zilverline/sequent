CREATE TABLE account_records%SUFFIX% (
    id serial NOT NULL,
    aggregate_id uuid NOT NULL,
    CONSTRAINT account_records_pkey%SUFFIX% PRIMARY KEY (id)
);

CREATE UNIQUE INDEX unique_aggregate_id%SUFFIX% ON account_records%SUFFIX% USING btree (aggregate_id);
