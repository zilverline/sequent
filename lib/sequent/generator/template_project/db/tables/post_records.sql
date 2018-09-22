CREATE TABLE post_records%SUFFIX% (
    id serial NOT NULL,
    aggregate_id uuid NOT NULL,
    author character varying,
    title character varying,
    content character varying,
    CONSTRAINT post_records_pkey%SUFFIX% PRIMARY KEY (id)
);

CREATE UNIQUE INDEX post_records_keys%SUFFIX% ON post_records%SUFFIX% USING btree (aggregate_id);
