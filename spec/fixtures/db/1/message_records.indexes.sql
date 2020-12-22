CREATE INDEX message_records_message%SUFFIX%
    ON message_records%SUFFIX% USING btree (message);
